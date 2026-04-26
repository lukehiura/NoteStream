import Foundation
import NoteStreamCore
import WhisperKit

public final class WhisperKitTranscriptionEngine: @unchecked Sendable, TranscriptionEngine {
  private let modelManager: WhisperKitModelManager

  public init(modelManager: WhisperKitModelManager = WhisperKitModelManager()) {
    self.modelManager = modelManager
  }

  public func prepare(model: String) async {
    await modelManager.prepare(model: model)
  }

  public func transcribeFile(
    at url: URL,
    model: String,
    onProgress: (@Sendable (NoteStreamTranscriptionProgress) -> Void)?
  ) async throws -> [TranscriptSegment] {
    let signposter = PerformanceSignposter(category: "transcription")
    let interval = signposter.beginInterval("final_transcription")
    defer { signposter.endInterval("final_transcription", state: interval) }

    let pipe = try await modelManager.getPipe(model: model)

    var options = DecodingOptions()
    options.task = .transcribe
    options.wordTimestamps = false

    let results: [TranscriptionResult] = try await pipe.transcribe(
      audioPath: url.path,
      decodeOptions: options,
      callback: { progress in
        onProgress?(
          NoteStreamTranscriptionProgress(windowId: progress.windowId, text: progress.text))
        return nil
      }
    )

    guard let result = results.first else { return [] }

    return result.segments.map { seg in
      TranscriptSegment(
        startTime: TimeInterval(seg.start),
        endTime: TimeInterval(seg.end),
        text: TranscriptSanitizer.cleanWhisperText(seg.text),
        status: .draft,
        confidence: nil
      )
    }
  }

  public func transcribeChunk(
    _ chunk: NoteStreamAudioChunk,
    model: String
  ) async throws -> [TranscriptSegment] {
    let pipe = try await modelManager.getPipe(model: model)

    // WhisperKit expects 16kHz mono Float array.
    let results: [TranscriptionResult] = try await pipe.transcribe(audioArray: chunk.samples)
    guard let result = results.first else { return [] }

    return result.segments.map { seg in
      TranscriptSegment(
        // Relative to the chunk; caller is responsible for shifting into absolute session time.
        startTime: TimeInterval(seg.start),
        endTime: TimeInterval(seg.end),
        text: TranscriptSanitizer.cleanWhisperText(seg.text),
        status: .draft,
        confidence: nil
      )
    }
  }
}
