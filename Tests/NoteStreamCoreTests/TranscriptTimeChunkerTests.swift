import Foundation
import Testing

@testable import NoteStreamCore

@Test func chunkSegmentsSplitsByTimeSpan() {
  let segments = [
    TranscriptSegment(
      startTime: 0, endTime: 200, text: "a", status: .committed),
    TranscriptSegment(
      startTime: 200, endTime: 400, text: "b", status: .committed),
    TranscriptSegment(
      startTime: 400, endTime: 700, text: "c", status: .committed),
  ]

  let chunks = TranscriptTimeChunker.chunkSegments(segments, maxSpanSeconds: 500)
  #expect(chunks.count == 2)
  #expect(chunks[0].count == 2)
  #expect(chunks[1].count == 1)
}

@Test func chunkSegmentsSingleWhenUnderLimit() {
  let segments = [
    TranscriptSegment(startTime: 0, endTime: 60, text: "x", status: .committed)
  ]
  let chunks = TranscriptTimeChunker.chunkSegments(segments, maxSpanSeconds: 480)
  #expect(chunks.count == 1)
  #expect(chunks[0].count == 1)
}
