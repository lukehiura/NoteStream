import Foundation

public enum TranscriptSegmentEditor {
  /// Splits one segment into two at a Swift `Character` offset in `segment.text`.
  public static func split(
    segments: [TranscriptSegment],
    segmentID: UUID,
    atCharacterOffset offset: Int
  ) -> [TranscriptSegment] {
    var sorted = segments.sorted { $0.startTime < $1.startTime }
    guard let index = sorted.firstIndex(where: { $0.id == segmentID }) else { return segments }

    let segment = sorted[index]
    let text = segment.text

    guard offset > 0, offset < text.count else { return segments }

    let splitIndex = text.index(text.startIndex, offsetBy: offset)
    let firstText = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !firstText.isEmpty, !secondText.isEmpty else { return segments }

    let midpoint = (segment.startTime + segment.endTime) / 2

    let first = TranscriptSegment(
      id: segment.id,
      startTime: segment.startTime,
      endTime: midpoint,
      text: firstText,
      status: segment.status,
      confidence: segment.confidence,
      speakerID: segment.speakerID,
      speakerName: segment.speakerName
    )

    let second = TranscriptSegment(
      startTime: midpoint,
      endTime: segment.endTime,
      text: secondText,
      status: segment.status,
      confidence: segment.confidence,
      speakerID: segment.speakerID,
      speakerName: segment.speakerName
    )

    sorted[index] = first
    sorted.insert(second, at: index + 1)

    return sorted
  }
}
