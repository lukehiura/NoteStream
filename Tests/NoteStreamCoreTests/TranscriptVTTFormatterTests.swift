import Testing

@testable import NoteStreamCore

@Test func vttFormatsCueTimestampsAndSpeaker() {
  let segments = [
    TranscriptSegment(
      startTime: 1.5,
      endTime: 3.25,
      text: "Hello",
      status: .committed,
      speakerName: "Speaker 1"
    )
  ]

  let vtt = TranscriptVTTFormatter.vtt(from: segments)

  #expect(vtt.hasPrefix("WEBVTT"))
  #expect(vtt.contains("00:00:01.500 --> 00:00:03.250"))
  #expect(vtt.contains("Speaker 1: Hello"))
}
