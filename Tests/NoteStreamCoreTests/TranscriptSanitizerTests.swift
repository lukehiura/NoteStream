import Foundation
import Testing

@testable import NoteStreamCore

@Test func trimsWhitespace() async throws {
  let seg = TranscriptSegment(
    startTime: 1, endTime: 2, text: "  hello \n world  ", status: .committed, confidence: nil)
  let cleaned = TranscriptSanitizer.sanitize([seg])
  #expect(cleaned.count == 1)
  #expect(cleaned[0].text == "hello world")
}

@Test func removesEmptySegments() async throws {
  let seg1 = TranscriptSegment(
    startTime: 1, endTime: 2, text: "   ", status: .committed, confidence: nil)
  let seg2 = TranscriptSegment(
    startTime: 2, endTime: 3, text: "\n", status: .committed, confidence: nil)
  let cleaned = TranscriptSanitizer.sanitize([seg1, seg2])
  #expect(cleaned.isEmpty)
}

@Test func removesCommonHallucinations() async throws {
  let seg = TranscriptSegment(
    startTime: 1, endTime: 2, text: "Thanks for watching", status: .committed, confidence: nil)
  let cleaned = TranscriptSanitizer.sanitize([seg])
  #expect(cleaned.isEmpty)
}

@Test func doesNotRemoveGenericThankYou() async throws {
  let seg = TranscriptSegment(
    startTime: 1, endTime: 2, text: "Thank you.", status: .committed, confidence: nil)
  let cleaned = TranscriptSanitizer.sanitize([seg])
  #expect(cleaned.count == 1)
  #expect(cleaned[0].text == "Thank you.")
}

@Test func preservesTimestamps() async throws {
  let seg = TranscriptSegment(
    startTime: 12.3, endTime: 45.6, text: "ok", status: .committed, confidence: nil)
  let cleaned = TranscriptSanitizer.sanitize([seg])
  #expect(cleaned.count == 1)
  #expect(cleaned[0].startTime == 12.3)
  #expect(cleaned[0].endTime == 45.6)
}
