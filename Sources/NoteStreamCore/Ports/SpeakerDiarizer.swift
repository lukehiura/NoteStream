import Foundation

public struct SpeakerTurn: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var startTime: TimeInterval
  public var endTime: TimeInterval
  public var speakerID: String
  public var confidence: Double?

  private enum CodingKeys: String, CodingKey {
    case id
    case startTime
    case endTime
    case speakerID
    case confidence
  }

  public init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    endTime: TimeInterval,
    speakerID: String,
    confidence: Double? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.speakerID = speakerID
    self.confidence = confidence
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    startTime = try c.decode(TimeInterval.self, forKey: .startTime)
    endTime = try c.decode(TimeInterval.self, forKey: .endTime)
    speakerID = try c.decode(String.self, forKey: .speakerID)
    confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(startTime, forKey: .startTime)
    try c.encode(endTime, forKey: .endTime)
    try c.encode(speakerID, forKey: .speakerID)
    try c.encodeIfPresent(confidence, forKey: .confidence)
  }
}

public struct SpeakerDiarizationResult: Codable, Sendable, Equatable {
  public var turns: [SpeakerTurn]
  public var speakerCount: Int

  public init(turns: [SpeakerTurn]) {
    let sorted = turns.sorted { $0.startTime < $1.startTime }
    self.turns = sorted
    self.speakerCount = Set(sorted.map(\.speakerID)).count
  }
}

public protocol SpeakerDiarizing: Sendable {
  func diarize(audioURL: URL, expectedSpeakerCount: Int?) async throws -> SpeakerDiarizationResult
}
