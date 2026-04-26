import Foundation

public enum SpeakerTurnAligner {
  public static func assignSpeakers(
    segments: [TranscriptSegment],
    turns: [SpeakerTurn],
    speakerLabels: [String: String] = [:]
  ) -> [TranscriptSegment] {
    segments.map { segment in
      var updated = segment

      if let speakerID = bestSpeakerID(for: segment, turns: turns) {
        updated.speakerID = speakerID
        updated.speakerName = speakerLabels[speakerID] ?? defaultSpeakerName(for: speakerID)
      }

      return updated
    }
  }

  private static func bestSpeakerID(
    for segment: TranscriptSegment,
    turns: [SpeakerTurn]
  ) -> String? {
    var bestSpeakerID: String?
    var bestOverlap: TimeInterval = 0

    for turn in turns {
      let start = Swift.max(segment.startTime, turn.startTime)
      let end = Swift.min(segment.endTime, turn.endTime)
      let overlap = Swift.max(0, end - start)

      if overlap > bestOverlap {
        bestOverlap = overlap
        bestSpeakerID = turn.speakerID
      }
    }

    return bestOverlap > 0 ? bestSpeakerID : nil
  }

  private static func defaultSpeakerName(for speakerID: String) -> String {
    if speakerID.hasPrefix("speaker_") {
      let suffix = speakerID.replacingOccurrences(of: "speaker_", with: "")
      return "Speaker \(suffix)"
    }

    return speakerID
  }
}
