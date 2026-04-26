import Foundation

public enum TranscriptVTTFormatter {
  public static func vtt(from segments: [TranscriptSegment]) -> String {
    let cues =
      segments
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { $0.startTime < $1.startTime }
      .map { segment in
        let speakerPrefix: String
        if let speakerName = segment.speakerName,
          !speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          speakerPrefix = "\(speakerName): "
        } else {
          speakerPrefix = ""
        }

        return """
          \(timestamp(segment.startTime)) --> \(timestamp(segment.endTime))
          \(speakerPrefix)\(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
          """
      }

    if cues.isEmpty {
      return "WEBVTT\n"
    }

    return "WEBVTT\n\n" + cues.joined(separator: "\n\n") + "\n"
  }

  private static func timestamp(_ seconds: TimeInterval) -> String {
    let totalMilliseconds = max(0, Int((seconds * 1000).rounded()))
    let milliseconds = totalMilliseconds % 1000
    let totalSeconds = totalMilliseconds / 1000
    let secs = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let mins = totalMinutes % 60
    let hours = totalMinutes / 60

    return String(format: "%02d:%02d:%02d.%03d", hours, mins, secs, milliseconds)
  }
}
