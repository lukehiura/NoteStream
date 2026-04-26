import Foundation

public struct LectureSession: Identifiable, Codable, Sendable, Equatable {
  public var id: UUID
  public var title: String
  public var createdAt: Date
  public var sourceFileName: String?
  /// Relative path within the session folder (e.g. "audio.caf"), if present.
  public var sourceAudioRelativePath: String?
  public var model: String
  public var segments: [TranscriptSegment]
  public var notesMarkdown: String?
  public var metadata: SessionMetadata

  public init(
    id: UUID = UUID(),
    title: String,
    createdAt: Date = Date(),
    sourceFileName: String? = nil,
    sourceAudioRelativePath: String? = nil,
    model: String,
    segments: [TranscriptSegment] = [],
    notesMarkdown: String? = nil,
    metadata: SessionMetadata = SessionMetadata()
  ) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
    self.sourceFileName = sourceFileName
    self.sourceAudioRelativePath = sourceAudioRelativePath
    self.model = model
    self.segments = segments
    self.notesMarkdown = notesMarkdown
    self.metadata = metadata
  }
}
