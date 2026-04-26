import Foundation
import XCTest

@testable import NoteStreamCore

final class SpeakerTurnAlignerTests: XCTestCase {
  func testAssignsSpeakerByLargestOverlap() async throws {
    let segments = [
      TranscriptSegment(startTime: 0, endTime: 5, text: "Hello", status: .committed),
      TranscriptSegment(startTime: 5, endTime: 10, text: "World", status: .committed),
    ]

    let turns = [
      SpeakerTurn(startTime: 0, endTime: 5, speakerID: "speaker_1"),
      SpeakerTurn(startTime: 5, endTime: 10, speakerID: "speaker_2"),
    ]

    let assigned = SpeakerTurnAligner.assignSpeakers(segments: segments, turns: turns)

    XCTAssertEqual(assigned[0].speakerID, "speaker_1")
    XCTAssertEqual(assigned[0].speakerName, "Speaker 1")
    XCTAssertEqual(assigned[1].speakerID, "speaker_2")
    XCTAssertEqual(assigned[1].speakerName, "Speaker 2")
  }

  func testKeepsSegmentUnlabeledWhenNoOverlap() async throws {
    let segments = [
      TranscriptSegment(startTime: 20, endTime: 25, text: "Late", status: .committed)
    ]

    let turns = [
      SpeakerTurn(startTime: 0, endTime: 5, speakerID: "speaker_1")
    ]

    let assigned = SpeakerTurnAligner.assignSpeakers(segments: segments, turns: turns)

    XCTAssertNil(assigned[0].speakerID)
    XCTAssertNil(assigned[0].speakerName)
  }
}
