import Foundation

public enum TranscriptSRTFormatter {
  public static func srt(from segments: [TranscriptSegment]) -> String {
    let nonempty =
      segments
      .sorted { $0.startTime < $1.startTime }
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    return nonempty.enumerated().map { index, segment in
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let speaker = segment.speakerName ?? segment.speakerID
      let displayText: String
      if let speaker, !speaker.isEmpty {
        displayText = "\(speaker): \(text)"
      } else {
        displayText = text
      }

      return
        "\(index + 1)\n\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n\(displayText)"
    }
    .joined(separator: "\n\n")
  }

  private static func formatSRTTime(_ seconds: TimeInterval) -> String {
    let totalMs = Int((seconds * 1000).rounded())
    let hours = totalMs / 3_600_000
    let minutes = (totalMs % 3_600_000) / 60_000
    let secs = (totalMs % 60_000) / 1000
    let ms = totalMs % 1000

    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, ms)
  }
}
