import Foundation

public struct RecordingQuestionRequest: Codable, Sendable, Equatable {
  public var transcriptMarkdown: String
  public var notesMarkdown: String?
  public var question: String

  public init(
    transcriptMarkdown: String,
    notesMarkdown: String?,
    question: String
  ) {
    self.transcriptMarkdown = transcriptMarkdown
    self.notesMarkdown = notesMarkdown
    self.question = question
  }
}

public struct RecordingQuestionAnswer: Codable, Sendable, Equatable {
  public var answerMarkdown: String
  public var citations: [TimeInterval]

  public init(answerMarkdown: String, citations: [TimeInterval] = []) {
    self.answerMarkdown = answerMarkdown
    self.citations = citations
  }
}

public protocol RecordingQuestionAnswering: Sendable {
  func answer(_ request: RecordingQuestionRequest) async throws -> RecordingQuestionAnswer
}
