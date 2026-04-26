import Foundation

public enum BoundaryType: Sendable {
  case vadPause
  case forcedMaxDuration
  case recordingStopped
}

/// Arbitrates transcript stability:
/// - committed is append-only and immutable
/// - draft may be revised until committed
public actor TranscriptCoordinator {
  private var committed: [TranscriptSegment] = []
  private var draft: [TranscriptSegment] = []
  private var lastCommittedEndTime: TimeInterval = 0
  private var audioHealth: AudioInputHealth = .ok
  private let sanitizer = TranscriptSanitizer()

  public init() {}

  public func snapshot(audioHealth: AudioInputHealth? = nil) -> TranscriptUpdate {
    if let audioHealth { self.audioHealth = audioHealth }
    return TranscriptUpdate(
      committed: committed,
      draft: draft,
      lastCommittedEndTime: lastCommittedEndTime,
      audioHealth: self.audioHealth
    )
  }

  /// Ingest rolling chunk output and return an updated stable/draft view.
  ///
  /// Policy:
  /// - Ignore anything that ends before the committed watermark (plus margin).
  /// - Keep overlapping region as draft; commit only older-than-delay segments.
  public func ingestRollingSegments(
    chunkStart: TimeInterval,
    chunkEnd: TimeInterval,
    segments: [TranscriptSegment],
    currentAudioTime: TimeInterval,
    boundary: BoundaryType,
    commitDelaySeconds: TimeInterval = 2,
    ignoreBeforeWatermarkMargin: TimeInterval = 0.2,
    audioHealth: AudioInputHealth = .ok
  ) -> TranscriptUpdate {
    self.audioHealth = audioHealth
    let watermark = max(0, lastCommittedEndTime - ignoreBeforeWatermarkMargin)

    // 1) Filter to only new-ish material.
    let incoming =
      segments
      .filter { $0.endTime > watermark }
      .map { seg in
        var s = seg
        s.status = .draft
        return s
      }

    // 2) Replace draft tail with incoming (rolling windows are allowed to revise draft).
    draft = incoming

    // 3) Commit any draft segments that are safely behind current audio time
    // (or everything if recording stopped).
    let commitCutoff: TimeInterval
    switch boundary {
    case .recordingStopped:
      commitCutoff = .greatestFiniteMagnitude
    case .vadPause, .forcedMaxDuration:
      commitCutoff = max(0, currentAudioTime - commitDelaySeconds)
    }

    var newlyCommitted: [TranscriptSegment] = []
    var remainingDraft: [TranscriptSegment] = []

    for seg in draft {
      let trimmedText = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if sanitizer.shouldDrop(trimmedText) { continue }

      if seg.endTime <= commitCutoff {
        var c = seg
        c.status = .committed
        newlyCommitted.append(c)
      } else {
        remainingDraft.append(seg)
      }
    }

    if !newlyCommitted.isEmpty {
      // Ensure strict monotonicity: only append segments that move forward.
      for seg in newlyCommitted.sorted(by: { $0.startTime < $1.startTime }) {
        if seg.endTime > lastCommittedEndTime {
          committed.append(seg)
          lastCommittedEndTime = max(lastCommittedEndTime, seg.endTime)
        }
      }
    }

    draft = remainingDraft

    return snapshot()
  }

  public func insertGap(start: TimeInterval, end: TimeInterval, reason: String? = nil)
    -> TranscriptUpdate
  {
    let text = reason.map { "Audio gap detected (\($0))" } ?? "Audio gap detected"
    let gap = TranscriptSegment(
      startTime: start, endTime: end, text: text, status: .gap, confidence: nil)
    committed.append(gap)
    lastCommittedEndTime = max(lastCommittedEndTime, end)
    return snapshot()
  }
}
