import Foundation
import XCTest

@testable import NoteStreamCore

final class TranscriptMarkdownFormatterTests: XCTestCase {
  func testMarkdownEmptySegmentsIsEmpty() async throws {
    XCTAssertTrue(TranscriptMarkdownFormatter.markdown(from: []).isEmpty)
  }

  func testMarkdownOneSegment() async throws {
    let seg = TranscriptSegment(startTime: 12, endTime: 15, text: "Hello", status: .committed)
    XCTAssertEqual(TranscriptMarkdownFormatter.markdown(from: [seg]), "[00:12] Hello")
  }

  func testMarkdownHourTimestamp() async throws {
    let seg = TranscriptSegment(startTime: 3661, endTime: 3662, text: "Hi", status: .committed)
    XCTAssertTrue(TranscriptMarkdownFormatter.markdown(from: [seg]).hasPrefix("[01:01:01]"))
  }

  func testMarkdownTrimsWhitespaceAndSkipsEmpty() async throws {
    let seg1 = TranscriptSegment(startTime: 0, endTime: 1, text: "  Hello  ", status: .committed)
    let seg2 = TranscriptSegment(startTime: 1, endTime: 2, text: "   ", status: .committed)
    XCTAssertEqual(TranscriptMarkdownFormatter.markdown(from: [seg1, seg2]), "[00:00] Hello")
  }

  func testMarkdownIncludesSpeakerWhenAvailable() async throws {
    let seg = TranscriptSegment(
      startTime: 12,
      endTime: 15,
      text: "Hello",
      status: .committed,
      speakerID: "speaker_1",
      speakerName: "Speaker 1"
    )

    XCTAssertEqual(TranscriptMarkdownFormatter.markdown(from: [seg]), "[00:12] Speaker 1: Hello")
  }
}
