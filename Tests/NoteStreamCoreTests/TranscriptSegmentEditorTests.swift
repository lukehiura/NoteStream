import Foundation
import XCTest

@testable import NoteStreamCore

final class TranscriptSegmentEditorTests: XCTestCase {
  func testSplitSegmentAtCharacterOffsetPreservesSpeakerAndTiming() {
    let id = UUID()

    let segments = [
      TranscriptSegment(
        id: id,
        startTime: 0,
        endTime: 10,
        text: "Hello world",
        status: .committed,
        speakerID: "speaker_1",
        speakerName: "Speaker 1"
      )
    ]

    let result = TranscriptSegmentEditor.split(
      segments: segments,
      segmentID: id,
      atCharacterOffset: 5
    )

    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result[0].text, "Hello")
    XCTAssertEqual(result[1].text, "world")
    XCTAssertEqual(result[0].endTime, 5)
    XCTAssertEqual(result[1].startTime, 5)
    XCTAssertEqual(result[1].speakerName, "Speaker 1")
  }

  func testSplitSegmentReturnsOriginalWhenOffsetInvalid() {
    let id = UUID()
    let segments = [
      TranscriptSegment(id: id, startTime: 0, endTime: 1, text: "ab", status: .committed)
    ]
    let unchanged = TranscriptSegmentEditor.split(
      segments: segments, segmentID: id, atCharacterOffset: 0)
    XCTAssertEqual(unchanged.count, 1)
  }
}
