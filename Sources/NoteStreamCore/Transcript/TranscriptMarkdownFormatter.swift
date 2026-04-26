import Foundation

public enum TranscriptMarkdownFormatter {
  public static func markdown(from segments: [TranscriptSegment]) -> String {
    let lines: [String] = segments.compactMap { seg in
      let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }

      let speaker = seg.speakerName ?? seg.speakerID

      if let speaker, !speaker.isEmpty {
        return "[\(formatTime(seg.startTime))] \(speaker): \(text)"
      }

      return "[\(formatTime(seg.startTime))] \(text)"
    }
    return lines.joined(separator: "\n")
  }

  private static func formatTime(_ t: TimeInterval) -> String {
    let total = Swift.max(0, Int(t.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
      return String(format: "%02d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
  }
}
