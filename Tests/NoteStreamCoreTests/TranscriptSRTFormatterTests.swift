import Testing

@testable import NoteStreamCore

@Test func srtFormatsCueTimestampsAndSpeaker() {
  let segments = [
    TranscriptSegment(
      startTime: 1.5,
      endTime: 3.25,
      text: "Hello",
      status: .committed,
      speakerName: "A"
    )
  ]
  let srt = TranscriptSRTFormatter.srt(from: segments)
  #expect(srt.hasPrefix("1\n"))
  #expect(srt.contains("00:00:01,500 --> 00:00:03,250"))
  #expect(srt.contains("A: Hello"))
}

@Test func srtSkipsWhitespaceOnlySegments() {
  let segments = [
    TranscriptSegment(startTime: 0, endTime: 1, text: "   ", status: .committed),
    TranscriptSegment(startTime: 1, endTime: 2, text: "Hi", status: .committed),
  ]
  let srt = TranscriptSRTFormatter.srt(from: segments)
  #expect(srt.hasPrefix("1\n"))
  #expect(srt.contains("Hi"))
  #expect(!srt.contains("   "))
}
