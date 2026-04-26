import Foundation
import NoteStreamCore

/// Runs a local executable that prints `[SpeakerTurn]` JSON on stdout.
public final class ExternalJSONSpeakerDiarizer: SpeakerDiarizing, @unchecked Sendable {
  private let executableURL: URL
  private let diagnostics: any DiagnosticsLogging
  private let additionalEnvironment: [String: String]

  public init(
    executableURL: URL,
    additionalEnvironment: [String: String] = [:],
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()
  ) {
    self.executableURL = executableURL
    self.additionalEnvironment = additionalEnvironment
    self.diagnostics = diagnostics
  }

  public func diarize(
    audioURL: URL,
    expectedSpeakerCount: Int?
  ) async throws -> SpeakerDiarizationResult {
    let exePath = executableURL.path
    let audioPath = audioURL.path
    let extraEnv = additionalEnvironment
    let expectedCount = expectedSpeakerCount

    let stdout = try await Task.detached(priority: .userInitiated) { () throws -> Data in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: exePath)

      var args = [
        "--audio",
        audioPath,
      ]

      if let expectedCount {
        args.append("--speakers")
        args.append("\(expectedCount)")
      }

      process.arguments = args

      var environment = ProcessInfo.processInfo.environment
      for (key, value) in extraEnv {
        environment[key] = value
      }
      process.environment = environment

      let output = Pipe()
      let errorPipe = Pipe()
      process.standardOutput = output
      process.standardError = errorPipe

      try process.run()
      process.waitUntilExit()

      let out = output.fileHandleForReading.readDataToEndOfFile()
      let err = errorPipe.fileHandleForReading.readDataToEndOfFile()

      guard process.terminationStatus == 0 else {
        let message = String(data: err, encoding: .utf8) ?? "Unknown diarization error"
        throw NSError(
          domain: "NoteStream", code: 70,
          userInfo: [
            NSLocalizedDescriptionKey: "Speaker diarization failed: \(message)"
          ])
      }

      return out
    }.value

    let decoder = JSONDecoder()
    let rawTurns = try decoder.decode([SpeakerTurn].self, from: stdout)
    let normalized = Self.normalizedTurns(rawTurns)
    let result = SpeakerDiarizationResult(turns: normalized)

    await diagnostics.log(
      .init(
        level: .info,
        category: "diarization",
        message: "external_diarizer_completed",
        metadata: [
          "turns": "\(result.turns.count)",
          "speakers": "\(result.speakerCount)",
        ]
      ))

    return result
  }

  private static func normalizedTurns(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
    var order: [String] = []
    var seen = Set<String>()
    for turn in turns {
      if seen.insert(turn.speakerID).inserted {
        order.append(turn.speakerID)
      }
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
