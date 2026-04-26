import Foundation
import XCTest

@testable import NoteStreamCore

final class NoteStreamErrorTests: XCTestCase {
  func testNoteStreamErrorDescriptionsAreNonEmpty() {
    let cases: [NoteStreamError] = [
      .noActiveRecording,
      .audioFileMissing,
      .diarizerNotConfigured,
      .notesSummarizerNotConfigured,
      .ollamaUnavailable("timeout"),
      .invalidLLMResponse("bad JSON"),
      .askRecordingUnsupported,
      .missingLLMBaseURL,
      .missingAnthropicAPIKey,
      .utf8EncodingFailed("notes"),
      .httpFailure(status: 500, body: "err"),
    ]
    for err in cases {
      XCTAssertGreaterThan(
        err.errorDescription?.count ?? 0,
        0,
        "Expected non-empty description for \(err)"
      )
    }
  }
}
