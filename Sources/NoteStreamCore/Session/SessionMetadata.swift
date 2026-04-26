import Foundation

public struct SessionMetadata: Codable, Sendable, Equatable {
  /// Increments when the on-disk session JSON shape gains new required semantics.
  public var schemaVersion: Int
  public var appVersion: String?
  public var createdAt: Date
  public var updatedAt: Date
  public var transcriptionStatus: String?
  public var errorMessage: String?

  public var speakerDiarizationStatus: String?
  public var speakerCount: Int?
  public var speakerLabels: [String: String]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case appVersion
    case createdAt
    case updatedAt
    case transcriptionStatus
    case errorMessage
    case speakerDiarizationStatus
    case speakerCount
    case speakerLabels
  }

  public init(
    schemaVersion: Int = SessionFileSchema.current,
    appVersion: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    transcriptionStatus: String? = nil,
    errorMessage: String? = nil,
    speakerDiarizationStatus: String? = nil,
    speakerCount: Int? = nil,
    speakerLabels: [String: String] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.appVersion = appVersion
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.transcriptionStatus = transcriptionStatus
    self.errorMessage = errorMessage
    self.speakerDiarizationStatus = speakerDiarizationStatus
    self.speakerCount = speakerCount
    self.speakerLabels = speakerLabels
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    transcriptionStatus = try c.decodeIfPresent(String.self, forKey: .transcriptionStatus)
    errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    speakerDiarizationStatus = try c.decodeIfPresent(String.self, forKey: .speakerDiarizationStatus)
    speakerCount = try c.decodeIfPresent(Int.self, forKey: .speakerCount)
    speakerLabels = try c.decodeIfPresent([String: String].self, forKey: .speakerLabels) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encodeIfPresent(appVersion, forKey: .appVersion)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(updatedAt, forKey: .updatedAt)
    try c.encodeIfPresent(transcriptionStatus, forKey: .transcriptionStatus)
    try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
    try c.encodeIfPresent(speakerDiarizationStatus, forKey: .speakerDiarizationStatus)
    try c.encodeIfPresent(speakerCount, forKey: .speakerCount)
    if !speakerLabels.isEmpty {
      try c.encode(speakerLabels, forKey: .speakerLabels)
    }
  }
}
