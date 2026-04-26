import Foundation
import Testing

@testable import NoteStreamCore

@Test func markdownEmptySegmentsIsEmpty() async throws {
  #expect(TranscriptMarkdownFormatter.markdown(from: []).isEmpty)
}

@Test func markdownOneSegment() async throws {
  let seg = TranscriptSegment(startTime: 12, endTime: 15, text: "Hello", status: .committed)
  #expect(TranscriptMarkdownFormatter.markdown(from: [seg]) == "[00:12] Hello")
}

@Test func markdownHourTimestamp() async throws {
  let seg = TranscriptSegment(startTime: 3661, endTime: 3662, text: "Hi", status: .committed)
  #expect(TranscriptMarkdownFormatter.markdown(from: [seg]).hasPrefix("[01:01:01]"))
}

@Test func markdownTrimsWhitespaceAndSkipsEmpty() async throws {
  let seg1 = TranscriptSegment(startTime: 0, endTime: 1, text: "  Hello  ", status: .committed)
  let seg2 = TranscriptSegment(startTime: 1, endTime: 2, text: "   ", status: .committed)
  #expect(TranscriptMarkdownFormatter.markdown(from: [seg1, seg2]) == "[00:00] Hello")
}

@Test func markdownIncludesSpeakerWhenAvailable() async throws {
  let seg = TranscriptSegment(
    startTime: 12,
    endTime: 15,
    text: "Hello",
    status: .committed,
    speakerID: "speaker_1",
    speakerName: "Speaker 1"
  )

  #expect(TranscriptMarkdownFormatter.markdown(from: [seg]) == "[00:12] Speaker 1: Hello")
}
