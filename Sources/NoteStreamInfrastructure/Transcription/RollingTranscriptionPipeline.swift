import Foundation
import NoteStreamCore

public struct RollingTranscriptPolicy: Sendable, Equatable {
  public var commitDelaySeconds: TimeInterval = 2
  public var vadConfig = VADChunkerConfig()

  public init() {}
}

/// Consumes audio frames and emits stable committed + draft transcript updates.
///
/// This pipeline is designed for "rolling transcription" (delayed, stable UI).
public actor RollingTranscriptionPipeline {
  private let transcriber: any TranscriptionEngine
  private let coordinator = TranscriptCoordinator()
  private let rms = RMSMeter()
  private var chunker = VADChunker()
  private var policy: RollingTranscriptPolicy
  private let diagnostics: any DiagnosticsLogging
  private var lastFrameSummaryTime: TimeInterval = 0
  private var healthMonitor = AudioHealthMonitor()
  private var lastEmittedHealth: AudioInputHealth = .ok

  public init(
    transcriber: any TranscriptionEngine,
    policy: RollingTranscriptPolicy = RollingTranscriptPolicy(),
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()
  ) {
    self.transcriber = transcriber
    self.policy = policy
    self.diagnostics = diagnostics
  }

  // swiftlint:disable:next cyclomatic_complexity
  public func run(
    frames: AsyncThrowingStream<AudioFrame, Error>,
    model: String
  ) -> AsyncThrowingStream<TranscriptUpdate, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          await transcriber.prepare(model: model)
          await diagnostics.info(.rolling, "rolling_pipeline_started", ["model": model])
          // Producer: frames -> VAD chunks
          let chunkStream = AsyncStream<NoteStreamAudioChunk>(
            bufferingPolicy: .bufferingNewest(8)
          ) { chunkCont in
            Task {
              var vad = SimpleVAD()
              let vadCfg = VADConfig()
              var droppedChunkCount = 0
              var lastDropLogTime: TimeInterval = 0

              do {
                for try await frame in frames {
                  if frame.sampleRateHz != 16_000 || frame.channelCount != 1 {
                    await diagnostics.log(
                      .init(
                        level: .warning, category: "rolling", message: "frame_skipped_non_16k_mono",
                        metadata: ["sr": "\(frame.sampleRateHz)", "ch": "\(frame.channelCount)"]))
                    continue
                  }

                  let level = rms.rms(of: frame.samples)
                  let health = healthMonitor.ingest(time: frame.startTime, rms: level)

                  // Instantly push state changes to the UI.
                  if health != lastEmittedHealth {
                    lastEmittedHealth = health
                    if health == .silentSuspected || health == .stalled {
                      // Drop any partial chunk state if input becomes unusable.
                      chunker = VADChunker()
                    }
                    let update = await coordinator.snapshot(audioHealth: health)
                    continuation.yield(update)
                    await diagnostics.log(
                      .init(
                        level: .warning,
                        category: "rolling",
                        message: "audio_health_changed",
                        metadata: ["state": health.rawValue]
                      ))
                  }

                  // Gatekeeper: avoid VAD work when input is known-bad.
                  if health == .silentSuspected || health == .stalled {
                    continue
                  }

                  let state = vad.ingestRMS(
                    time: frame.startTime, rms: Double(level), config: vadCfg)
                  let speechLike = (state == .speech)

                  if !speechLike && level < 0.015 {
                    vad.calibrateNoiseFloor(with: Double(level))
                  }

                  if frame.startTime - lastFrameSummaryTime >= 1.0 {
                    lastFrameSummaryTime = frame.startTime
                    await diagnostics.log(
                      .init(
                        level: .debug, category: "rolling", message: "rolling_frame_summary",
                        metadata: [
                          "t": "\(frame.startTime)",
                          "rms": "\(level)",
                          "speechLike": "\(speechLike)",
                        ]))
                  }

                  if let chunk = chunker.ingest(
                    frame: frame, isSpeechLike: speechLike, config: policy.vadConfig)
                  {
                    await diagnostics.log(
                      .init(
                        level: .info, category: "rolling", message: "vad_chunk_emitted",
                        metadata: [
                          "start": "\(chunk.startTime)",
                          "end": "\(chunk.endTime)",
                          "samples": "\(chunk.samples.count)",
                        ]))
                    let yieldResult = chunkCont.yield(chunk)
                    if case .dropped = yieldResult {
                      droppedChunkCount += 1
                      if frame.startTime - lastDropLogTime >= 1.0 {
                        lastDropLogTime = frame.startTime
                        await diagnostics.log(
                          .init(
                            level: .error,
                            category: "rolling",
                            message: "chunk_dropped_backpressure",
                            metadata: [
                              "droppedTotal": "\(droppedChunkCount)",
                              "bufferingPolicy": "bufferingNewest(8)",
                              "chunkStart": "\(chunk.startTime)",
                              "chunkEnd": "\(chunk.endTime)",
                              "chunkSeconds": "\(chunk.endTime - chunk.startTime)",
                            ]
                          ))
                      }
                    }
                  }
                }
                chunkCont.finish()
              } catch {
                chunkCont.finish()
                continuation.finish(throwing: error)
              }
            }
          }

          // Consumer: chunks -> Whisper -> transcript updates
          for await chunk in chunkStream {
            let health = lastEmittedHealth
            if health == .silentSuspected || health == .stalled {
              continue
            }

            await diagnostics.info(
              .rolling,
              "chunk_transcription_started",
              [
                "start": "\(chunk.startTime)",
                "end": "\(chunk.endTime)",
              ])
            let t0 = Date()
            let rawSegments = try await transcriber.transcribeChunk(chunk, model: model)
            let dt = Date().timeIntervalSince(t0)
            await diagnostics.info(
              .rolling,
              "chunk_transcription_completed",
              [
                "segments": "\(rawSegments.count)",
                "inferenceSeconds": "\(dt)",
                "audioSeconds": "\(chunk.endTime - chunk.startTime)",
              ])

            let shifted = rawSegments.map { seg in
              TranscriptSegment(
                startTime: seg.startTime + chunk.startTime,
                endTime: seg.endTime + chunk.startTime,
                text: TranscriptSanitizer.cleanWhisperText(seg.text),
                status: seg.status,
                confidence: seg.confidence
              )
            }
            let update = await coordinator.ingestRollingSegments(
              chunkStart: chunk.startTime,
              chunkEnd: chunk.endTime,
              segments: shifted,
              currentAudioTime: chunk.endTime,
              boundary: .vadPause,
              commitDelaySeconds: policy.commitDelaySeconds,
              audioHealth: health
            )
            await diagnostics.log(
              .init(
                level: .debug, category: "rolling", message: "transcript_update_emitted",
                metadata: [
                  "committed": "\(update.committed.count)",
                  "draft": "\(update.draft.count)",
                ]))
            continuation.yield(update)
          }

          // End of chunks: commit everything remaining.
          let finalUpdate = await coordinator.ingestRollingSegments(
            chunkStart: 0,
            chunkEnd: 0,
            segments: [],
            currentAudioTime: .greatestFiniteMagnitude,
            boundary: .recordingStopped,
            audioHealth: lastEmittedHealth
          )
          continuation.yield(finalUpdate)
          await diagnostics.info(.rolling, "rolling_pipeline_stopped", [:])
          continuation.finish()
        } catch {
          await diagnostics.error(
            .rolling,
            "chunk_transcription_failed",
            error,
            [:]
          )
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
