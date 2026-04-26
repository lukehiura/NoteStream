import Foundation
import NoteStreamCore
import Testing

@testable import NoteStreamInfrastructure

private func writeExecutableScript(directory: URL, name: String, contents: String) throws -> URL {
  let url = directory.appendingPathComponent(name)
  try contents.write(to: url, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  return url
}

@Suite("ExternalJSONNotesSummarizer")
struct ExternalJSONNotesSummarizerTests {
  @Test func parsesValidJSONFromStdout() async throws {
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

    #expect(result.title == "Lecture")
    #expect(result.summaryMarkdown.contains("Summary"))
    #expect(result.keyPoints == ["a"])
  }

  @Test func surfacesStderrOnNonZeroExit() async throws {
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
      try await summarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: "hello",
          previousNotesMarkdown: nil,
          mode: .final
        )
      )
      Issue.record("Expected summarize to throw")
    } catch let error as NSError {
      #expect(error.localizedDescription.contains("simulated adapter failure"))
    }
  }
}

@Suite("ExternalJSONSpeakerDiarizer")
struct ExternalJSONSpeakerDiarizerTests {
  @Test func parsesSpeakerTurnsJSON() async throws {
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

    #expect(result.turns.count == 2)
    #expect(result.speakerCount == 2)
    #expect(result.turns.allSatisfy { $0.speakerID.hasPrefix("speaker_") })
  }

  @Test func nonZeroExitPropagatesMessage() async throws {
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
      try await diarizer.diarize(audioURL: audio, expectedSpeakerCount: nil)
      Issue.record("Expected diarize to throw")
    } catch let error as NSError {
      #expect(error.localizedDescription.contains("diarizer stderr"))
    }
  }

  @Test func speakerDiarizerPassesHuggingFaceTokenEnvironment() async throws {
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

    #expect(result.turns.count == 1)
    #expect(result.turns[0].speakerID == "speaker_1")
  }
}
