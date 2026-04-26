import Foundation
import NoteStreamCore

/// Runs a local executable: JSON `NotesSummarizationRequest` on stdin, `NotesSummary` JSON on stdout.
public final class ExternalJSONNotesSummarizer: NotesSummarizing, @unchecked Sendable {
  private let executableURL: URL
  private let diagnostics: any DiagnosticsLogging

  public init(
    executableURL: URL,
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()
  ) {
    self.executableURL = executableURL
    self.diagnostics = diagnostics
  }

  public func summarize(_ request: NotesSummarizationRequest) async throws -> NotesSummary {
    let encoder = JSONEncoder()
    let input = try encoder.encode(request)
    let exePath = executableURL.path

    let (exitStatus, outputData, errorData) = try await Task.detached(priority: .userInitiated) {
      () throws -> (Int32, Data, Data) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: exePath)
      process.arguments = []

      let stdin = Pipe()
      let stdout = Pipe()
      let stderr = Pipe()

      process.standardInput = stdin
      process.standardOutput = stdout
      process.standardError = stderr

      try process.run()

      stdin.fileHandleForWriting.write(input)
      try stdin.fileHandleForWriting.close()

      process.waitUntilExit()

      let out = stdout.fileHandleForReading.readDataToEndOfFile()
      let err = stderr.fileHandleForReading.readDataToEndOfFile()
      return (process.terminationStatus, out, err)
    }.value

    guard exitStatus == 0 else {
      let message = String(data: errorData, encoding: .utf8) ?? "Unknown notes summarizer error"

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

    let decoder = JSONDecoder()
    let summary = try decoder.decode(NotesSummary.self, from: outputData)

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
