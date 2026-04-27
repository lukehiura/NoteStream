import Foundation

/// Shared time formatting for library rows, playback UI, and transcript cues.
enum DurationFormatting {
  /// Segment / library summary, e.g. `"2m 5s"` or `"1h 3m"`.
  static func compact(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
      return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
    if m > 0 {
      return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }
    return "\(s)s"
  }

  /// Playback / header clock, e.g. `3:02` or `1:03:02`.
  static func playbackClock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
  }

  /// Zero-padded transcript cue time, e.g. `00:01:05` or `01:32`.
  static func timestamp(_ seconds: TimeInterval) -> String {
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
