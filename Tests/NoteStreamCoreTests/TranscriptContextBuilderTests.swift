import Foundation
import XCTest

@testable import NoteStreamCore

final class TranscriptContextBuilderTests: XCTestCase {
  func testTranscriptContextBuilderOmitsDraftAndGap() {
    let segments: [TranscriptSegment] = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "A", status: .committed),
      TranscriptSegment(startTime: 1, endTime: 2, text: "B", status: .draft),
      TranscriptSegment(startTime: 2, endTime: 3, text: "C", status: .gap),
    ]
    let md = TranscriptContextBuilder.markdown(from: segments)
    XCTAssertTrue(md.contains("A"))
    XCTAssertFalse(md.contains("B"))
    XCTAssertFalse(md.contains("C"))
  }

  func testTranscriptContextBuilderStartingAfterFiltersByEndTime() {
    let segments: [TranscriptSegment] = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "early", status: .committed),
      TranscriptSegment(startTime: 5, endTime: 7, text: "late", status: .committed),
    ]
    let md = TranscriptContextBuilder.markdown(from: segments, startingAfter: 1)
    XCTAssertFalse(md.contains("early"))
    XCTAssertTrue(md.contains("late"))
  }

  func testTranscriptContextBuilderLastEndTime() {
    let segments: [TranscriptSegment] = [
      TranscriptSegment(startTime: 0, endTime: 3, text: "x", status: .committed),
      TranscriptSegment(startTime: 4, endTime: 10, text: "y", status: .committed),
    ]
    XCTAssertEqual(TranscriptContextBuilder.lastEndTime(from: segments), 10)
  }

  func testTranscriptContextBuilderLastEndTimeEmpty() {
    XCTAssertEqual(TranscriptContextBuilder.lastEndTime(from: []), 0)
  }
}
