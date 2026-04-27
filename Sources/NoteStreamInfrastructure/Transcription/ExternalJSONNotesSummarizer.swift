import Foundation
import NoteStreamCore

/// Runs a local executable: JSON `NotesSummarizationRequest` on stdin, `NotesSummary` JSON on stdout.
public final class ExternalJSONNotesSummarizer: NotesSummarizing, @unchecked Sendable {
  private let executableURL: URL
  private let diagnostics: any DiagnosticsLogging
  private let timeoutSeconds: UInt64

  public init(
    executableURL: URL,
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger(),
    timeoutSeconds: UInt64 = 120
  ) {
    self.executableURL = executableURL
    self.diagnostics = diagnostics
    self.timeoutSeconds = timeoutSeconds
  }

  public func summarize(_ request: NotesSummarizationRequest) async throws -> NotesSummary {
    let input = try JSONEncoder().encode(request)

    let result = try await ExternalProcessRunner.run(
      executableURL: executableURL,
      stdin: input,
      timeoutSeconds: timeoutSeconds
    )

    guard result.terminationStatus == 0 else {
      let message =
        String(data: result.stderr, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "Unknown notes summarizer error"

      await diagnostics.log(
        .init(
          level: .error,
          category: "notes",
          message: "notes_summarizer_failed",
          metadata: ["error": message]
        ))

      throw NSError(
        domain: "NoteStream", code: 80,
        userInfo: [
          NSLocalizedDescriptionKey: "Notes summarizer failed: \(message)"
        ])
    }

    let summary = try JSONDecoder().decode(NotesSummary.self, from: result.stdout)

    await diagnostics.log(
      .init(
        level: .info,
        category: "notes",
        message: "notes_summarizer_completed",
        metadata: ["title": summary.title]
      ))

    return summary
  }
}
