import Foundation

/// Splits transcript segments into time-bounded groups for staged LLM summarization.
public enum TranscriptTimeChunker {
  /// Each chunk’s time span from first segment start to last segment end is at most `maxSpanSeconds`.
  public static func chunkSegments(
    _ segments: [TranscriptSegment],
    maxSpanSeconds: TimeInterval
  ) -> [[TranscriptSegment]] {
    let sorted = segments.sorted { $0.startTime < $1.startTime }
    guard !sorted.isEmpty, maxSpanSeconds > 0 else { return sorted.isEmpty ? [] : [sorted] }

    var chunks: [[TranscriptSegment]] = []
    var current: [TranscriptSegment] = []
    var chunkStart = sorted[0].startTime

    for seg in sorted {
      if current.isEmpty {
        current.append(seg)
        chunkStart = seg.startTime
        continue
      }

      let maxEndSoFar = current.map(\.endTime).max() ?? seg.endTime
      let mergedEnd = max(maxEndSoFar, seg.endTime)

      if mergedEnd - chunkStart > maxSpanSeconds {
        chunks.append(current)
        current = [seg]
        chunkStart = seg.startTime
      } else {
        current.append(seg)
      }
    }

    if !current.isEmpty {
      chunks.append(current)
    }

    return chunks
  }
}
