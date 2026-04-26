import Foundation

public struct NoteStreamTranscriptionProgress: Sendable, Equatable {
  public var windowId: Int
  public var text: String

  public init(windowId: Int, text: String) {
    self.windowId = windowId
    self.text = text
  }
}

public protocol TranscriptionEngine: Sendable {
  func prepare(model: String) async

  func transcribeFile(
    at url: URL,
    model: String,
    onProgress: (@Sendable (NoteStreamTranscriptionProgress) -> Void)?
  ) async throws -> [TranscriptSegment]

  func transcribeChunk(
    _ chunk: NoteStreamAudioChunk,
    model: String
  ) async throws -> [TranscriptSegment]
}
