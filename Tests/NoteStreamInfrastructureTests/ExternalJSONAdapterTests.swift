import Foundation
import NoteStreamCore
import XCTest

@testable import NoteStreamInfrastructure

private func writeExecutableScript(directory: URL, name: String, contents: String) throws -> URL {
  let url = directory.appendingPathComponent(name)
  try contents.write(to: url, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  return url
}

final class ExternalJSONNotesSummarizerTests: XCTestCase {
  func testParsesValidJSONFromStdout() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let script = try writeExecutableScript(
      directory: tmp,
      name: "notes_ok.sh",
      contents: """
        #!/bin/sh
        cat >/dev/null
        printf '%s\\n' '{"title":"Lecture","summaryMarkdown":"## Summary\\nOK","keyPoints":["a"],"actionItems":[],"openQuestions":[]}'
        """
    )

    let summarizer = ExternalJSONNotesSummarizer(executableURL: script)
    let result = try await summarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: "hello",
        previousNotesMarkdown: nil,
        mode: .final
      )
    )

    XCTAssertEqual(result.title, "Lecture")
    XCTAssertTrue(result.summaryMarkdown.contains("Summary"))
    XCTAssertEqual(result.keyPoints, ["a"])
  }

  func testSurfacesStderrOnNonZeroExit() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let script = try writeExecutableScript(
      directory: tmp,
      name: "notes_fail.sh",
      contents: """
        #!/bin/sh
        cat >/dev/null
        echo 'simulated adapter failure' >&2
        exit 1
        """
    )

    let summarizer = ExternalJSONNotesSummarizer(executableURL: script)

    do {
      _ = try await summarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: "hello",
          previousNotesMarkdown: nil,
          mode: .final
        )
      )
      XCTFail("Expected summarize to throw")
    } catch let error as NSError {
      XCTAssertTrue(error.localizedDescription.contains("simulated adapter failure"))
    }
  }

  /// Verifies stderr is drained concurrently with stdout so large stderr cannot deadlock the pipe buffer.
  func testLargeStderrStillReturnsStdoutJSON() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let script = try writeExecutableScript(
      directory: tmp,
      name: "notes_big_stderr.sh",
      contents: """
        #!/bin/sh
        cat >/dev/null
        i=0
        while [ "$i" -lt 4000 ]; do
          echo "stderr padding xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" >&2
          i=$((i + 1))
        done
        printf '%s\\n' '{"title":"BigStderr","summaryMarkdown":"ok","keyPoints":[],"actionItems":[],"openQuestions":[]}'
        """
    )

    let summarizer = ExternalJSONNotesSummarizer(executableURL: script)
    let result = try await summarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: "hello",
        previousNotesMarkdown: nil,
        mode: .final
      )
    )

    XCTAssertEqual(result.title, "BigStderr")
    XCTAssertEqual(result.summaryMarkdown, "ok")
  }

  func testTimeoutThrows() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let script = try writeExecutableScript(
      directory: tmp,
      name: "notes_slow.sh",
      contents: """
        #!/bin/sh
        cat >/dev/null
        while :; do
          :
        done
        """
    )

    let summarizer = ExternalJSONNotesSummarizer(executableURL: script, timeoutSeconds: 1)
    let start = Date()

    do {
      _ = try await summarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: "hello",
          previousNotesMarkdown: nil,
          mode: .final
        )
      )
      XCTFail("Expected summarize to throw on timeout")
    } catch let error as NSError {
      let elapsed = Date().timeIntervalSince(start)

      XCTAssertEqual(error.domain, "NoteStream")
      XCTAssertEqual(error.code, 71)
      XCTAssertTrue(error.localizedDescription.contains("timed out"))
      XCTAssertLessThan(
        elapsed, 5,
        "Timeout test should finish quickly."
      )
    }
  }
}

final class ExternalJSONSpeakerDiarizerTests: XCTestCase {
  func testParsesSpeakerTurnsJSON() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let audio = tmp.appendingPathComponent("fake.caf")
    try Data([0]).write(to: audio)

    let script = try writeExecutableScript(
      directory: tmp,
      name: "diarize_ok.sh",
      contents: """
        #!/bin/sh
        printf '%s\\n' '[{"startTime":0,"endTime":2,"speakerID":"alice"},{"startTime":1,"endTime":3,"speakerID":"bob"}]'
        """
    )

    let diarizer = ExternalJSONSpeakerDiarizer(executableURL: script)
    let result = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: 2)

    XCTAssertEqual(result.turns.count, 2)
    XCTAssertEqual(result.speakerCount, 2)
    XCTAssertTrue(result.turns.allSatisfy { $0.speakerID.hasPrefix("speaker_") })
  }

  func testNonZeroExitPropagatesMessage() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let audio = tmp.appendingPathComponent("fake.caf")
    try Data([0]).write(to: audio)

    let script = try writeExecutableScript(
      directory: tmp,
      name: "diarize_fail.sh",
      contents: """
        #!/bin/sh
        echo 'diarizer stderr' >&2
        exit 2
        """
    )

    let diarizer = ExternalJSONSpeakerDiarizer(executableURL: script)

    do {
      _ = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: nil)
      XCTFail("Expected diarize to throw")
    } catch let error as NSError {
      XCTAssertTrue(error.localizedDescription.contains("diarizer stderr"))
    }
  }

  func testSpeakerDiarizerPassesHuggingFaceTokenEnvironment() async throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let audio = tmp.appendingPathComponent("fake.caf")
    try Data([0]).write(to: audio)

    let script = try writeExecutableScript(
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
      ]
    )

    let result = try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: 1)

    XCTAssertEqual(result.turns.count, 1)
    XCTAssertEqual(result.turns[0].speakerID, "speaker_1")
  }
}
