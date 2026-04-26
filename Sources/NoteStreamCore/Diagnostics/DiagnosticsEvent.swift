import Foundation

public struct DiagnosticsEvent: Codable, Sendable, Identifiable {
  public var id: UUID
  public var timestamp: Date
  public var level: DiagnosticsLevel
  public var category: String
  public var message: String
  public var metadata: [String: String]

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    level: DiagnosticsLevel,
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.timestamp = timestamp
    self.level = level
    self.category = category
    self.message = message
    self.metadata = metadata
  }
}
