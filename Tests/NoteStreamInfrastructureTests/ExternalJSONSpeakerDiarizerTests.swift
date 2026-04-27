import Foundation
import NoteStreamCore
import NoteStreamTestSupport
import XCTest

@testable import NoteStreamInfrastructure

final class ExternalJSONSpeakerDiarizerTests: XCTestCase {
  func testParsesSpeakerTurnsJSON() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamAdapter") { tmp in
      let audio = tmp.appendingPathComponent("fake.caf")
      try Data([0]).write(to: audio)

      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "diarize_ok.sh",
        contents: """
          #!/bin/sh
          printf '%s\\n' '[{"startTime":0,"endTime":2,"speakerID":"alice"},{"startTime":1,"endTime":3,"speakerID":"bob"}]'
          """
      )

      let diarizer = ExternalJSONSpeakerDiarizer(executableURL: script, timeoutSeconds: 5)
      let result = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: 2)

      XCTAssertEqual(result.turns.count, 2)
      XCTAssertEqual(result.speakerCount, 2)
      XCTAssertTrue(result.turns.allSatisfy { $0.speakerID.hasPrefix("speaker_") })
    }
  }

  func testNonZeroExitPropagatesMessage() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamAdapter") { tmp in
      let audio = tmp.appendingPathComponent("fake.caf")
      try Data([0]).write(to: audio)

      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "diarize_fail.sh",
        contents: """
          #!/bin/sh
          echo 'diarizer stderr' >&2
          exit 2
          """
      )

      let diarizer = ExternalJSONSpeakerDiarizer(executableURL: script, timeoutSeconds: 5)

      do {
        _ = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: nil)
        XCTFail("Expected diarize to throw")
      } catch let error as NSError {
        XCTAssertTrue(error.localizedDescription.contains("diarizer stderr"))
      }
    }
  }

  func testSpeakerDiarizerPassesHuggingFaceTokenEnvironment() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamAdapter") { tmp in
      let audio = tmp.appendingPathComponent("fake.caf")
      try Data([0]).write(to: audio)

      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "diarize_env.sh",
        contents: """
          #!/bin/sh
          if [ "$HF_TOKEN" != "hf_test_token" ]; then
            echo "missing HF_TOKEN" >&2
            exit 3
          fi

          printf '%s\\n' '[{"startTime":0,"endTime":2,"speakerID":"alice"}]'
          """
      )

      let diarizer = ExternalJSONSpeakerDiarizer(
        executableURL: script,
        additionalEnvironment: [
          "HF_TOKEN": "hf_test_token"
        ],
        timeoutSeconds: 5
      )

      let result = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: 1)

      XCTAssertEqual(result.turns.count, 1)
      XCTAssertEqual(result.turns[0].speakerID, "speaker_1")
    }
  }
}
