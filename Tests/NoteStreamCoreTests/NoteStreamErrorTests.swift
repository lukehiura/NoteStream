import Foundation
import Testing

@testable import NoteStreamCore

@Test func noteStreamErrorDescriptionsAreNonEmpty() {
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
    #expect(err.errorDescription?.isEmpty == false)
  }
}
