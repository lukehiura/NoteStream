import Foundation

public struct LiveSpeakerDiarizationUpdate: Sendable, Equatable {
  public var turns: [SpeakerTurn]
  public var isFinalForWindow: Bool
  public var windowStartTime: TimeInterval
  public var windowEndTime: TimeInterval

  public init(
    turns: [SpeakerTurn],
    isFinalForWindow: Bool,
    windowStartTime: TimeInterval,
    windowEndTime: TimeInterval
  ) {
    self.turns = turns
    self.isFinalForWindow = isFinalForWindow
    self.windowStartTime = windowStartTime
    self.windowEndTime = windowEndTime
  }
}

/// Rolling / streaming speaker diarization (contrasts with batch ``SpeakerDiarizing`` on a full file).
public protocol LiveSpeakerDiarizing: Sendable {
  func start(expectedSpeakerCount: Int?) async throws
  func ingest(frame: AudioFrame) async throws -> LiveSpeakerDiarizationUpdate?
  func finish() async throws -> LiveSpeakerDiarizationUpdate?
  func reset() async
}
