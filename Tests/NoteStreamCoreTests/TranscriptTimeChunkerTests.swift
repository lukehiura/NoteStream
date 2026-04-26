import Foundation
import XCTest

@testable import NoteStreamCore

final class TranscriptTimeChunkerTests: XCTestCase {
  func testChunkSegmentsSplitsByTimeSpan() {
    let segments = [
      TranscriptSegment(
        startTime: 0, endTime: 200, text: "a", status: .committed),
      TranscriptSegment(
        startTime: 200, endTime: 400, text: "b", status: .committed),
      TranscriptSegment(
        startTime: 400, endTime: 700, text: "c", status: .committed),
    ]

    let chunks = TranscriptTimeChunker.chunkSegments(segments, maxSpanSeconds: 500)
    XCTAssertEqual(chunks.count, 2)
    XCTAssertEqual(chunks[0].count, 2)
    XCTAssertEqual(chunks[1].count, 1)
  }

  func testChunkSegmentsSingleWhenUnderLimit() {
    let segments = [
      TranscriptSegment(startTime: 0, endTime: 60, text: "x", status: .committed)
    ]
    let chunks = TranscriptTimeChunker.chunkSegments(segments, maxSpanSeconds: 480)
    XCTAssertEqual(chunks.count, 1)
    XCTAssertEqual(chunks[0].count, 1)
  }
}
