import Foundation
import NoteStreamCore

/// Deterministic fake turns for DEBUG builds so speaker UI and persistence can be exercised without an external binary.
public struct DebugSpeakerDiarizer: SpeakerDiarizing, Sendable {
  public init() {}

  public func diarize(
    audioURL: URL,
    expectedSpeakerCount: Int?
  ) async throws -> SpeakerDiarizationResult {
    let count = max(1, expectedSpeakerCount ?? 2)
    var turns: [SpeakerTurn] = []

    var t: TimeInterval = 0
    while t < 60 * 60 {
      let speakerNumber = (Int(t / 8) % count) + 1
      turns.append(
        SpeakerTurn(
          startTime: t,
          endTime: t + 8,
          speakerID: "speaker_\(speakerNumber)",
          confidence: 1.0
        )
      )
      t += 8
    }

    return SpeakerDiarizationResult(turns: turns)
  }
}
