import Foundation
import NoteStreamCore

/// Runs a local executable that prints `[SpeakerTurn]` JSON on stdout.
public final class ExternalJSONSpeakerDiarizer: SpeakerDiarizing, @unchecked Sendable {
  private let executableURL: URL
  private let diagnostics: any DiagnosticsLogging
  private let additionalEnvironment: [String: String]
  private let timeoutSeconds: UInt64

  public init(
    executableURL: URL,
    additionalEnvironment: [String: String] = [:],
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger(),
    timeoutSeconds: UInt64 = 300
  ) {
    self.executableURL = executableURL
    self.additionalEnvironment = additionalEnvironment
    self.diagnostics = diagnostics
    self.timeoutSeconds = timeoutSeconds
  }

  public func diarize(
    audioURL: URL,
    expectedSpeakerCount: Int?
  ) async throws -> SpeakerDiarizationResult {
    var arguments = [
      "--audio",
      audioURL.path,
    ]

    if let expectedSpeakerCount {
      arguments.append("--speakers")
      arguments.append("\(expectedSpeakerCount)")
    }

    let result = try await ExternalProcessRunner.run(
      executableURL: executableURL,
      arguments: arguments,
      additionalEnvironment: additionalEnvironment,
      timeoutSeconds: timeoutSeconds
    )

    guard result.terminationStatus == 0 else {
      let message =
        String(data: result.stderr, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "Unknown diarization error"

      throw NSError(
        domain: "NoteStream", code: 70,
        userInfo: [
          NSLocalizedDescriptionKey: "Speaker diarization failed: \(message)"
        ])
    }

    let rawTurns = try JSONDecoder().decode([SpeakerTurn].self, from: result.stdout)
    let normalized = Self.normalizedTurns(rawTurns)
    let output = SpeakerDiarizationResult(turns: normalized)

    await diagnostics.log(
      .init(
        level: .info,
        category: "diarization",
        message: "external_diarizer_completed",
        metadata: [
          "turns": "\(output.turns.count)",
          "speakers": "\(output.speakerCount)",
        ]
      ))

    return output
  }

  private static func normalizedTurns(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
    var order: [String] = []
    var seen = Set<String>()
    for turn in turns where seen.insert(turn.speakerID).inserted {
      order.append(turn.speakerID)
    }
    let mapping = Dictionary(
      uniqueKeysWithValues: order.enumerated().map { index, oldID in
        (oldID, "speaker_\(index + 1)")
      })

    return turns.map { turn in
      var updated = turn
      updated.speakerID = mapping[turn.speakerID] ?? turn.speakerID
      return updated
    }
  }
}
