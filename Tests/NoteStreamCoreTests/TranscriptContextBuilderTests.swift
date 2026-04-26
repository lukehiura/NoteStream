import Foundation
import Testing

@testable import NoteStreamCore

@Test func transcriptContextBuilderOmitsDraftAndGap() {
  let segments: [TranscriptSegment] = [
    TranscriptSegment(startTime: 0, endTime: 1, text: "A", status: .committed),
    TranscriptSegment(startTime: 1, endTime: 2, text: "B", status: .draft),
    TranscriptSegment(startTime: 2, endTime: 3, text: "C", status: .gap),
  ]
  let md = TranscriptContextBuilder.markdown(from: segments)
  #expect(md.contains("A"))
  #expect(!md.contains("B"))
  #expect(!md.contains("C"))
}

@Test func transcriptContextBuilderStartingAfterFiltersByEndTime() {
  let segments: [TranscriptSegment] = [
    TranscriptSegment(startTime: 0, endTime: 1, text: "early", status: .committed),
    TranscriptSegment(startTime: 5, endTime: 7, text: "late", status: .committed),
  ]
  let md = TranscriptContextBuilder.markdown(from: segments, startingAfter: 1)
  #expect(!md.contains("early"))
  #expect(md.contains("late"))
}

@Test func transcriptContextBuilderLastEndTime() {
  let segments: [TranscriptSegment] = [
    TranscriptSegment(startTime: 0, endTime: 3, text: "x", status: .committed),
    TranscriptSegment(startTime: 4, endTime: 10, text: "y", status: .committed),
  ]
  #expect(TranscriptContextBuilder.lastEndTime(from: segments) == 10)
}

@Test func transcriptContextBuilderLastEndTimeEmpty() {
  #expect(TranscriptContextBuilder.lastEndTime(from: []) == 0)
}
