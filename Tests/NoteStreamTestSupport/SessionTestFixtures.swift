import Foundation
import NoteStreamCore

public enum SessionTestFixtures {
  public static func lectureSession(
    id: UUID = UUID(),
    title: String = "Test Lecture",
    sourceFileName: String = "test.m4a",
    model: String = "base.en",
    segments: [TranscriptSegment] = [
      TranscriptSegment(startTime: 0, endTime: 1, text: "Hello", status: .committed),
      TranscriptSegment(startTime: 1, endTime: 2, text: "world", status: .committed),
    ],
    notesMarkdown: String? = nil
  ) -> LectureSession {
    LectureSession(
      id: id,
      title: title,
      sourceFileName: sourceFileName,
      model: model,
      segments: segments,
      notesMarkdown: notesMarkdown
    )
  }

  public static func segment(
    startTime: TimeInterval = 0,
    endTime: TimeInterval = 1,
    text: String = "Hello",
    status: SegmentStatus = .committed
  ) -> TranscriptSegment {
    TranscriptSegment(startTime: startTime, endTime: endTime, text: text, status: status)
  }
}
