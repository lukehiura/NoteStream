import Foundation

public enum SegmentStatus: String, Codable, Sendable {
  case draft
  case committed
  case gap
  case silence
}

public struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let startTime: TimeInterval
  public let endTime: TimeInterval
  public var text: String
  public var status: SegmentStatus
  public var confidence: Double?
  /// Stable diarization id, e.g. `speaker_1`.
  public var speakerID: String?
  /// Display label, e.g. `Speaker 1` or user-renamed `Professor`.
  public var speakerName: String?

  public init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    endTime: TimeInterval,
    text: String,
    status: SegmentStatus,
    confidence: Double? = nil,
    speakerID: String? = nil,
    speakerName: String? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.text = text
    self.status = status
    self.confidence = confidence
    self.speakerID = speakerID
    self.speakerName = speakerName
  }
}

public struct TranscriptUpdate: Sendable, Equatable {
  public var committed: [TranscriptSegment]
  public var draft: [TranscriptSegment]
  public var lastCommittedEndTime: TimeInterval
  public var audioHealth: AudioInputHealth

  public init(
    committed: [TranscriptSegment],
    draft: [TranscriptSegment],
    lastCommittedEndTime: TimeInterval,
    audioHealth: AudioInputHealth = .ok
  ) {
    self.committed = committed
    self.draft = draft
    self.lastCommittedEndTime = lastCommittedEndTime
    self.audioHealth = audioHealth
  }
}
