import XCTest

@testable import NoteStreamCore

final class TranscriptVTTFormatterTests: XCTestCase {
  func testVttFormatsCueTimestampsAndSpeaker() {
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

    XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
    XCTAssertTrue(vtt.contains("00:00:01.500 --> 00:00:03.250"))
    XCTAssertTrue(vtt.contains("Speaker 1: Hello"))
  }
}
