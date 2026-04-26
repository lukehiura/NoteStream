import Foundation

public struct RecordingSession: Identifiable, Sendable, Equatable {
  public var id: UUID
  public var startedAt: Date
  public var outputURL: URL

  public init(id: UUID = UUID(), startedAt: Date = Date(), outputURL: URL) {
    self.id = id
    self.startedAt = startedAt
    self.outputURL = outputURL
  }
}
