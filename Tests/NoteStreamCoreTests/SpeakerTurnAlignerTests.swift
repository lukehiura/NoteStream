import Foundation
import Testing

@testable import NoteStreamCore

@Test func assignsSpeakerByLargestOverlap() async throws {
  let segments = [
    TranscriptSegment(startTime: 0, endTime: 5, text: "Hello", status: .committed),
    TranscriptSegment(startTime: 5, endTime: 10, text: "World", status: .committed),
  ]

  let turns = [
    SpeakerTurn(startTime: 0, endTime: 5, speakerID: "speaker_1"),
    SpeakerTurn(startTime: 5, endTime: 10, speakerID: "speaker_2"),
  ]

  let assigned = SpeakerTurnAligner.assignSpeakers(segments: segments, turns: turns)

  #expect(assigned[0].speakerID == "speaker_1")
  #expect(assigned[0].speakerName == "Speaker 1")
  #expect(assigned[1].speakerID == "speaker_2")
  #expect(assigned[1].speakerName == "Speaker 2")
}

@Test func keepsSegmentUnlabeledWhenNoOverlap() async throws {
  let segments = [
    TranscriptSegment(startTime: 20, endTime: 25, text: "Late", status: .committed)
  ]

  let turns = [
    SpeakerTurn(startTime: 0, endTime: 5, speakerID: "speaker_1")
  ]

  let assigned = SpeakerTurnAligner.assignSpeakers(segments: segments, turns: turns)

  #expect(assigned[0].speakerID == nil)
  #expect(assigned[0].speakerName == nil)
}
