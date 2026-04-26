import Foundation
import XCTest

@testable import NoteStreamCore

final class TranscriptSanitizerTests: XCTestCase {
  func testTrimsWhitespace() async throws {
    let seg = TranscriptSegment(
      startTime: 1, endTime: 2, text: "  hello \n world  ", status: .committed, confidence: nil)
    let cleaned = TranscriptSanitizer.sanitize([seg])
    XCTAssertEqual(cleaned.count, 1)
    XCTAssertEqual(cleaned[0].text, "hello world")
  }

  func testRemovesEmptySegments() async throws {
    let seg1 = TranscriptSegment(
      startTime: 1, endTime: 2, text: "   ", status: .committed, confidence: nil)
    let seg2 = TranscriptSegment(
      startTime: 2, endTime: 3, text: "\n", status: .committed, confidence: nil)
    let cleaned = TranscriptSanitizer.sanitize([seg1, seg2])
    XCTAssertTrue(cleaned.isEmpty)
  }

  func testRemovesCommonHallucinations() async throws {
    let seg = TranscriptSegment(
      startTime: 1, endTime: 2, text: "Thanks for watching", status: .committed, confidence: nil)
    let cleaned = TranscriptSanitizer.sanitize([seg])
    XCTAssertTrue(cleaned.isEmpty)
  }

  func testDoesNotRemoveGenericThankYou() async throws {
    let seg = TranscriptSegment(
      startTime: 1, endTime: 2, text: "Thank you.", status: .committed, confidence: nil)
    let cleaned = TranscriptSanitizer.sanitize([seg])
    XCTAssertEqual(cleaned.count, 1)
    XCTAssertEqual(cleaned[0].text, "Thank you.")
  }

  func testPreservesTimestamps() async throws {
    let seg = TranscriptSegment(
      startTime: 12.3, endTime: 45.6, text: "ok", status: .committed, confidence: nil)
    let cleaned = TranscriptSanitizer.sanitize([seg])
    XCTAssertEqual(cleaned.count, 1)
    XCTAssertEqual(cleaned[0].startTime, 12.3)
    XCTAssertEqual(cleaned[0].endTime, 45.6)
  }
}
