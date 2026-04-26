import XCTest

@testable import NoteStreamCore

final class TranscriptSRTFormatterTests: XCTestCase {
  func testSrtFormatsCueTimestampsAndSpeaker() {
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
    XCTAssertTrue(srt.hasPrefix("1\n"))
    XCTAssertTrue(srt.contains("00:00:01,500 --> 00:00:03,250"))
    XCTAssertTrue(srt.contains("A: Hello"))
  }

  func testSrtSkipsWhitespaceOnlySegments() {
    let segments = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "   ", status: .committed),
      TranscriptSegment(startTime: 1, endTime: 2, text: "Hi", status: .committed),
    ]
    let srt = TranscriptSRTFormatter.srt(from: segments)
    XCTAssertTrue(srt.hasPrefix("1\n"))
    XCTAssertTrue(srt.contains("Hi"))
    XCTAssertFalse(srt.contains("   "))
  }
}
