import Foundation
import NoteStreamCore
import NoteStreamTestSupport
import XCTest

@testable import NoteStreamInfrastructure

final class ExternalJSONNotesSummarizerTests: XCTestCase {
  func testParsesValidJSONFromStdout() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamAdapter") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "notes_ok.sh",
        contents: """
          #!/bin/sh
          cat >/dev/null
          printf '%s\\n' '{"title":"Lecture","summaryMarkdown":"## Summary\\nOK","keyPoints":["a"],"actionItems":[],"openQuestions":[]}'
          """
      )

      let summarizer = ExternalJSONNotesSummarizer(executableURL: script, timeoutSeconds: 5)
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
  }

  func testSurfacesStderrOnNonZeroExit() async throws {
    try await TestTemp.withTemporaryDirectory(prefix: "NoteStreamAdapter") { tmp in
      let script = try TestScript.writeExecutable(
        directory: tmp,
        name: "notes_fail.sh",
        contents: """
          #!/bin/sh
          cat >/dev/null
          echo 'simulated adapter failure' >&2
          exit 1
          """
      )

      let summarizer = ExternalJSONNotesSummarizer(executableURL: script, timeoutSeconds: 5)

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
  }
}
