import Foundation
import Testing

@testable import NoteStreamCore

@Test func splitSegmentAtCharacterOffsetPreservesSpeakerAndTiming() {
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

  #expect(result.count == 2)
  #expect(result[0].text == "Hello")
  #expect(result[1].text == "world")
  #expect(result[0].endTime == 5)
  #expect(result[1].startTime == 5)
  #expect(result[1].speakerName == "Speaker 1")
}

@Test func splitSegmentReturnsOriginalWhenOffsetInvalid() {
  let id = UUID()
  let segments = [
    TranscriptSegment(id: id, startTime: 0, endTime: 1, text: "ab", status: .committed)
  ]
  let unchanged = TranscriptSegmentEditor.split(
    segments: segments, segmentID: id, atCharacterOffset: 0)
  #expect(unchanged.count == 1)
}
