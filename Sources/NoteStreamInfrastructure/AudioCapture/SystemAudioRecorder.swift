import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import NoteStreamCore
import ScreenCaptureKit

private final class OneShotResume: @unchecked Sendable {
  private let lock = NSLock()
  private var didResume = false

  func run(_ block: () -> Void) {
    lock.lock()
    defer { lock.unlock() }

    guard !didResume else { return }
    didResume = true
    block()
  }
}

private func withStartupTimeout<T>(
  seconds: UInt64,
  message: String,
  operation: @escaping @Sendable () async throws -> T,
  onTimeout: (@Sendable () -> Void)? = nil
) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    let gate = OneShotResume()

    let operationTask = Task {
      do {
        let value = try await operation()
        gate.run {
          continuation.resume(returning: value)
        }
      } catch {
        gate.run {
          continuation.resume(throwing: error)
        }
      }
    }

    Task {
      try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)

      gate.run {
        operationTask.cancel()
        onTimeout?()

        continuation.resume(
          throwing: NSError(
            domain: "NoteStream", code: 13,
            userInfo: [NSLocalizedDescriptionKey: message]
          ))
      }
    }
  }
}

public final class SystemAudioRecorder: NSObject, @unchecked Sendable, AudioRecorder {
  private let writer = AssetWriter()
  private let frames = AudioFrameBroadcaster()
  private let resampler = AudioResampler()
  private let baseDiagnostics: any DiagnosticsLogging

  private var stream: SCStream?
  private var outputURL: URL?
  private var sessionDiagnostics: (any DiagnosticsLogging)?
  private var firstFrameStartTime: TimeInterval?
  private var sampleQueue: DispatchQueue?
  private var samplesReceived: Int = 0
  private var framesPublished: Int = 0
  private var lastStreamSummaryTime: TimeInterval = 0

  public init(diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()) {
    self.baseDiagnostics = diagnostics
    super.init()
  }

  private func resetPartialRecordingState() async {
    stream = nil
    outputURL = nil
    sampleQueue = nil
    sessionDiagnostics = nil
    firstFrameStartTime = nil
    samplesReceived = 0
    framesPublished = 0
    lastStreamSummaryTime = 0

    await frames.finishAll()
    writer.reset()
  }

  public func audioFrames() async -> AsyncStream<AudioFrame> {
    await frames.stream()
  }

  public func startRecording(outputURL: URL) async throws -> RecordingSession {
    await baseDiagnostics.log(
      .init(level: .info, category: "recorder", message: "recording_start_requested"))
    if stream != nil {
      throw NSError(
        domain: "NoteStream", code: 10,
        userInfo: [
          NSLocalizedDescriptionKey: "Recording already in progress."
        ])
    }

    do {
      self.outputURL = outputURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      try await writer.start(outputURL: outputURL)

      // Per-session diagnostics file.
      let sessionLogURL = outputURL.deletingLastPathComponent().appendingPathComponent(
        "diagnostics.jsonl")
      sessionDiagnostics = CompositeDiagnosticsLogger([
        baseDiagnostics,
        FileDiagnosticsLogger(logURL: sessionLogURL),
      ])
      await sessionDiagnostics?.log(
        .init(
          level: .info, category: "recorder", message: "session_diagnostics_started",
          metadata: ["path": sessionLogURL.path]))

      let screenPreflight = String(CGPreflightScreenCaptureAccess())
      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_pipeline_begin",
          metadata: [
            "screenCapturePreflight": screenPreflight,
            "output": outputURL.lastPathComponent,
          ]
        ))

      // Pick the main display.
      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_fetch_shareable_content_begin",
          metadata: ["timeoutSeconds": "5", "screenCapturePreflight": screenPreflight]
        ))

      let shareableT0 = CFAbsoluteTimeGetCurrent()
      let diagSink = sessionDiagnostics
      let content = try await withStartupTimeout(
        seconds: 5,
        message: "Timed out fetching ScreenCaptureKit shareable content.",
        operation: {
          try await SCShareableContent.current
        },
        onTimeout: {
          Task {
            await diagSink?.log(
              .init(
                level: .error,
                category: "recorder",
                message: "sck_fetch_shareable_content_timeout",
                metadata: [
                  "timeoutSeconds": "5",
                  "screenCapturePreflight": String(CGPreflightScreenCaptureAccess()),
                  "hint":
                    "SCShareableContent.current did not finish within the timeout. Check Screen Recording permission, close other capture apps, or retry after a few seconds.",
                ]
              ))
          }
        }
      )
      let shareableMs = Int((CFAbsoluteTimeGetCurrent() - shareableT0) * 1000)
      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_fetch_shareable_content_ok",
          metadata: [
            "elapsedMs": "\(shareableMs)",
            "displayCount": "\(content.displays.count)",
            "windowCount": "\(content.windows.count)",
          ]
        ))
      guard let display = content.displays.first else {
        throw NSError(
          domain: "NoteStream", code: 11,
          userInfo: [
            NSLocalizedDescriptionKey: "No display found for ScreenCaptureKit."
          ])
      }

      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_display_selected",
          metadata: [
            "displayID": "\(display.displayID)",
            "width": "\(display.width)",
            "height": "\(display.height)",
          ]
        ))

      let filter = SCContentFilter(display: display, excludingWindows: [])

      let config = SCStreamConfiguration()
      config.capturesAudio = true
      config.sampleRate = 48_000
      config.channelCount = 2

      // Keep video overhead low; we don't add a video output.
      config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
      config.width = 2
      config.height = 2

      let stream = SCStream(filter: filter, configuration: config, delegate: nil)

      let sampleQueue = DispatchQueue(label: "NoteStream.AudioFrames")
      self.sampleQueue = sampleQueue
      try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_start_capture_begin",
          metadata: [
            "timeoutSeconds": "5",
            "screenCapturePreflight": String(CGPreflightScreenCaptureAccess()),
            "displayID": "\(display.displayID)",
          ]
        ))

      // Start capture with a timeout that does not wait on a hung `startCapture` finishing.
      let captureStream = stream
      let captureT0 = CFAbsoluteTimeGetCurrent()
      let diagForCaptureTimeout = sessionDiagnostics
      try await withStartupTimeout(
        seconds: 5,
        message: "Timed out starting ScreenCaptureKit capture.",
        operation: {
          try await captureStream.startCapture()
        },
        onTimeout: { [weak self] in
          let sc = captureStream
          Task { [weak self] in
            await diagForCaptureTimeout?.log(
              .init(
                level: .error,
                category: "recorder",
                message: "sck_start_capture_timeout",
                metadata: [
                  "timeoutSeconds": "5",
                  "screenCapturePreflight": String(CGPreflightScreenCaptureAccess()),
                  "hint":
                    "SCStream.startCapture did not finish within the timeout. Often permission, system load, or another app holding ScreenCaptureKit. Check Console / app diagnostics log.",
                ]
              ))
            guard let self else { return }
            try? sc.removeStreamOutput(self, type: .audio)
            try? await sc.stopCapture()
          }
        }
      )
      let captureMs = Int((CFAbsoluteTimeGetCurrent() - captureT0) * 1000)
      await sessionDiagnostics?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "sck_start_capture_ok",
          metadata: ["elapsedMs": "\(captureMs)"]
        ))

      self.stream = captureStream
      await sessionDiagnostics?.log(
        .init(
          level: .info, category: "recorder", message: "recording_started",
          metadata: ["output": outputURL.lastPathComponent]))
      firstFrameStartTime = nil
      return RecordingSession(outputURL: outputURL)
    } catch {
      let ns = error as NSError
      let meta: [String: String] = [
        "error": String(describing: error),
        "domain": ns.domain,
        "code": "\(ns.code)",
        "localizedDescription": ns.localizedDescription,
        "screenCapturePreflight": String(CGPreflightScreenCaptureAccess()),
      ]
      let sink = sessionDiagnostics ?? baseDiagnostics
      await sink.log(
        .init(
          level: .error,
          category: "recorder",
          message: "recording_start_failed",
          metadata: meta
        ))

      await resetPartialRecordingState()

      throw error
    }
  }

  public func stopRecording() async throws -> URL {
    guard let url = outputURL else {
      await resetPartialRecordingState()

      throw NSError(
        domain: "NoteStream", code: 12,
        userInfo: [
          NSLocalizedDescriptionKey: "No active recording."
        ])
    }

    guard let stream else {
      await resetPartialRecordingState()

      throw NSError(
        domain: "NoteStream", code: 12,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Recording did not fully start. Partial capture state was reset."
        ])
    }

    let diag = sessionDiagnostics
    var stopCaptureError: Error?

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await stream.stopCapture() }
        group.addTask {
          try await Task.sleep(nanoseconds: 8_000_000_000)
          throw NSError(
            domain: "NoteStream", code: 14,
            userInfo: [
              NSLocalizedDescriptionKey: "Timed out stopping ScreenCaptureKit capture."
            ])
        }

        try await group.next()
        group.cancelAll()
      }
    } catch {
      stopCaptureError = error
      await diag?.log(
        .init(
          level: .error,
          category: "recorder",
          message: "stop_capture_failed_continuing_to_finalize_audio",
          metadata: ["error": String(describing: error)]
        ))
    }

    self.stream = nil
    self.outputURL = nil
    self.sampleQueue = nil
    self.firstFrameStartTime = nil
    self.samplesReceived = 0
    self.framesPublished = 0
    self.lastStreamSummaryTime = 0

    await frames.finishAll()

    do {
      try await writer.finish()
    } catch {
      await diag?.log(
        .init(
          level: .error,
          category: "recorder",
          message: "writer_finish_failed",
          metadata: ["error": String(describing: error)]
        ))
      throw error
    }

    if let stopCaptureError {
      await diag?.log(
        .init(
          level: .warning,
          category: "recorder",
          message: "recording_stopped_after_capture_stop_error",
          metadata: ["error": String(describing: stopCaptureError)]
        ))
    } else {
      await diag?.log(
        .init(
          level: .info,
          category: "recorder",
          message: "recording_stopped",
          metadata: ["output": url.lastPathComponent]
        ))
    }

    sessionDiagnostics = nil
    return url
  }
}

extension SystemAudioRecorder: SCStreamOutput {
  public func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio else { return }
    let outputURL = self.outputURL
    let diag = self.sessionDiagnostics
    samplesReceived += 1

    if let outputURL {
      writer.queue.async { [weak self] in
        self?.writer.append(sampleBuffer: sampleBuffer, outputURL: outputURL)
      }
    }

    if let frame16k = resampler.process(sampleBuffer: sampleBuffer) {
      let base = firstFrameStartTime ?? frame16k.startTime
      if firstFrameStartTime == nil { firstFrameStartTime = base }
      let relative = AudioFrame(
        startTime: max(0, frame16k.startTime - base),
        samples: frame16k.samples,
        sampleRateHz: frame16k.sampleRateHz,
        channelCount: frame16k.channelCount
      )
      framesPublished += 1
      Task { await frames.publish(relative) }
    } else {
      Task {
        await diag?.log(
          .init(level: .warning, category: "recorder", message: "audio_frame_conversion_failed"))
      }
    }

    // Summary once per second (relative time), instead of per-buffer spam.
    let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    if t - lastStreamSummaryTime >= 1.0 {
      lastStreamSummaryTime = t
      let samples = samplesReceived
      let framesOut = framesPublished
      samplesReceived = 0
      framesPublished = 0
      Task {
        await diag?.log(
          .init(
            level: .debug,
            category: "recorder",
            message: "audio_stream_summary",
            metadata: [
              "t": "\(t)",
              "sampleBuffers": "\(samples)",
              "framesPublished": "\(framesOut)",
            ]
          ))
      }
    }
  }
}

private actor AudioFrameBroadcaster {
  private var continuations: [UUID: AsyncStream<AudioFrame>.Continuation] = [:]

  func stream() -> AsyncStream<AudioFrame> {
    AsyncStream { continuation in
      let id = UUID()
      continuations[id] = continuation
      continuation.onTermination = { @Sendable [weak self] _ in
        Task { await self?.remove(id: id) }
      }
    }
  }

  func publish(_ frame: AudioFrame) {
    for c in continuations.values {
      c.yield(frame)
    }
  }

  func finishAll() {
    for c in continuations.values {
      c.finish()
    }
    continuations.removeAll()
  }

  private func remove(id: UUID) {
    continuations.removeValue(forKey: id)
  }
}

private final class AssetWriter: @unchecked Sendable {
  let queue = DispatchQueue(label: "NoteStream.AudioFileWriter")

  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var hasStartedSession = false
  private var lastError: Error?

  func start(outputURL: URL) async throws {
    try queue.sync {
      self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
      self.hasStartedSession = false
      self.lastError = nil
    }
  }

  func append(sampleBuffer: CMSampleBuffer, outputURL: URL) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    guard lastError == nil else { return }

    if writer == nil {
      do {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
      } catch {
        lastError = error
        return
      }
    }

    guard let writer else { return }

    if input == nil {
      // Use explicit PCM settings. "Passthrough" can fail depending on the incoming format.
      let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) {
        writer.add(input)
        self.input = input
      } else {
        lastError = NSError(
          domain: "NoteStream", code: 21,
          userInfo: [
            NSLocalizedDescriptionKey: "AVAssetWriter cannot add audio input.",
            "fileType": "caf",
            "outputSettings": outputSettings,
          ])
        return
      }

      if writer.startWriting() == false {
        lastError =
          writer.error
          ?? NSError(
            domain: "NoteStream", code: 22,
            userInfo: [
              NSLocalizedDescriptionKey: "AVAssetWriter failed to start writing."
            ])
        return
      }
    }

    guard let input else { return }
    if !hasStartedSession {
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      writer.startSession(atSourceTime: pts)
      hasStartedSession = true
    }

    if input.isReadyForMoreMediaData == false {
      return
    }

    if input.append(sampleBuffer) == false {
      lastError =
        writer.error
        ?? NSError(
          domain: "NoteStream", code: 23,
          userInfo: [
            NSLocalizedDescriptionKey: "AVAssetWriterInput failed to append sample buffer."
          ])
    }
  }

  func finish() async throws {
    let snapshot = queue.sync {
      (
        writer: self.writer,
        input: self.input,
        hasStartedSession: self.hasStartedSession,
        lastError: self.lastError
      )
    }

    if let lastError = snapshot.lastError {
      reset()
      throw lastError
    }

    guard let writer = snapshot.writer else {
      reset()
      return
    }

    guard snapshot.hasStartedSession, snapshot.input != nil else {
      writer.cancelWriting()
      reset()
      return
    }

    snapshot.input?.markAsFinished()

    let box = AssetWriterBox(writer)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      box.writer.finishWriting {
        if let err = box.writer.error {
          cont.resume(throwing: err)
        } else {
          cont.resume(returning: ())
        }
      }
    }

    reset()
  }

  func reset() {
    queue.sync {
      self.input = nil
      self.writer = nil
      self.hasStartedSession = false
      self.lastError = nil
    }
  }
}

private final class AssetWriterBox: @unchecked Sendable {
  let writer: AVAssetWriter
  init(_ writer: AVAssetWriter) { self.writer = writer }
}
