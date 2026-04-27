import Foundation
import NoteStreamTestSupport
import XCTest

@testable import NoteStreamInfrastructure

final class ExternalProcessRunnerTests: XCTestCase {
  func testLargeStderrStillDrainsAndReturnsStdout() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamRunner") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "big_stderr.sh",
        contents: """
          #!/bin/sh
          cat >/dev/null
          i=0
          while [ "$i" -lt 4000 ]; do
            echo "stderr padding xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" >&2
            i=$((i + 1))
          done
          printf '%s\\n' '{"out":"ok"}'
          """
      )

      let result = try await ExternalProcessRunner.run(
        executableURL: script,
        arguments: [],
        stdin: Data("{}".utf8),
        timeoutSeconds: 10
      )

      XCTAssertEqual(result.terminationStatus, 0)

      let obj = try JSONSerialization.jsonObject(with: result.stdout) as? [String: String]
      XCTAssertEqual(obj?["out"], "ok")
      XCTAssertFalse(result.stderr.isEmpty)
    }
  }

  func testNonzeroExitStillReturnsStderrBytes() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamRunner") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "nonzero.sh",
        contents: """
          #!/bin/sh
          echo 'runner failed clearly' >&2
          exit 42
          """
      )

      let result = try await ExternalProcessRunner.run(
        executableURL: script,
        timeoutSeconds: 5
      )

      XCTAssertEqual(result.terminationStatus, 42)
      XCTAssertEqual(
        String(data: result.stderr, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        "runner failed clearly"
      )
    }
  }

  func testPassesAdditionalEnvironment() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamRunner") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "env.sh",
        contents: """
          #!/bin/sh
          if [ "$HF_TOKEN" != "hf_test_token" ]; then
            echo "missing HF_TOKEN" >&2
            exit 3
          fi

          printf '%s\\n' 'env ok'
          """
      )

      let result = try await ExternalProcessRunner.run(
        executableURL: script,
        additionalEnvironment: [
          "HF_TOKEN": "hf_test_token"
        ],
        timeoutSeconds: 5
      )

      XCTAssertEqual(result.terminationStatus, 0)
      XCTAssertEqual(
        String(data: result.stdout, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        "env ok"
      )
    }
  }

  func testNilStdinDoesNotHang() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamRunner") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "no_stdin.sh",
        contents: """
          #!/bin/sh
          printf '%s\\n' 'no stdin ok'
          """
      )

      let result = try await ExternalProcessRunner.run(
        executableURL: script,
        stdin: nil,
        timeoutSeconds: 5
      )

      XCTAssertEqual(result.terminationStatus, 0)
      XCTAssertEqual(
        String(data: result.stdout, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines),
        "no stdin ok"
      )
    }
  }

  func testTimeoutTerminatesProcess() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamRunner") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "infinite.sh",
        contents: """
          #!/bin/sh
          while :; do
            :
          done
          """
      )

      let start = Date()

      do {
        _ = try await ExternalProcessRunner.run(
          executableURL: script,
          timeoutSeconds: 1
        )
        XCTFail("Expected timeout")
      } catch let error as NSError {
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(error.domain, "NoteStream")
        XCTAssertEqual(error.code, 71)
        XCTAssertTrue(error.localizedDescription.contains("timed out"))
        XCTAssertLessThan(elapsed, 5)
      }
    }
  }
}
