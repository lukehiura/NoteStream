import Foundation

enum TranscriptFormatting {
  static func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60

    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, s)
    }

    return String(format: "%d:%02d", m, s)
  }

  static func formatTimestamp(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60

    if h > 0 {
      return String(format: "%02d:%02d:%02d", h, m, s)
    }

    return String(format: "%02d:%02d", m, s)
  }
}
