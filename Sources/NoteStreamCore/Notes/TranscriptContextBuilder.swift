import Foundation

public enum TranscriptContextBuilder {
  public static func markdown(
    from segments: [TranscriptSegment],
    startingAfter startTime: TimeInterval? = nil
  ) -> String {
    let filtered =
      segments
      .filter { segment in
        guard segment.status == .committed else { return false }
        if let startTime {
          return segment.endTime > startTime
        }
        return true
      }
      .sorted { $0.startTime < $1.startTime }

    return TranscriptMarkdownFormatter.markdown(from: filtered)
  }

  public static func lastEndTime(from segments: [TranscriptSegment]) -> TimeInterval {
    segments.map(\.endTime).max() ?? 0
  }
}
