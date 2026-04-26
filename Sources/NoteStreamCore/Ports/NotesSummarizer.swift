import Foundation

public enum NotesSummarizationMode: String, Codable, Sendable {
  case final
  case liveUpdate
}

public struct NotesSummarizationRequest: Codable, Sendable, Equatable {
  public var transcriptMarkdown: String
  public var previousNotesMarkdown: String?
  public var mode: NotesSummarizationMode
  public var preferences: NotesGenerationPreferences

  enum CodingKeys: String, CodingKey {
    case transcriptMarkdown
    case previousNotesMarkdown
    case mode
    case preferences
  }

  public init(
    transcriptMarkdown: String,
    previousNotesMarkdown: String? = nil,
    mode: NotesSummarizationMode,
    preferences: NotesGenerationPreferences = .standard
  ) {
    self.transcriptMarkdown = transcriptMarkdown
    self.previousNotesMarkdown = previousNotesMarkdown
    self.mode = mode
    self.preferences = preferences
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    transcriptMarkdown = try c.decode(String.self, forKey: .transcriptMarkdown)
    previousNotesMarkdown = try c.decodeIfPresent(String.self, forKey: .previousNotesMarkdown)
    mode = try c.decode(NotesSummarizationMode.self, forKey: .mode)
    preferences =
      try c.decodeIfPresent(NotesGenerationPreferences.self, forKey: .preferences)
      ?? .standard
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(transcriptMarkdown, forKey: .transcriptMarkdown)
    try c.encodeIfPresent(previousNotesMarkdown, forKey: .previousNotesMarkdown)
    try c.encode(mode, forKey: .mode)
    try c.encode(preferences, forKey: .preferences)
  }
}

public protocol NotesSummarizing: Sendable {
  func summarize(_ request: NotesSummarizationRequest) async throws -> NotesSummary
}
