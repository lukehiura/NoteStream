import Foundation
import NoteStreamCore

/// Shared display strings for sessions in the library and when saving recordings.
enum SessionUIFormatting {
  /// Compact title for a saved recording (e.g. "Apr 26, 12:12 AM").
  static func recordingSessionTitle(startedAt: Date) -> String {
    startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened))
  }

  /// Primary line for a library row: file base name for imports, otherwise stored title.
  static func libraryPrimaryTitle(for session: LectureSession) -> String {
    if let name = session.sourceFileName, !name.isEmpty {
      return (name as NSString).deletingPathExtension
    }
    return session.title
  }

  /// One-line subtitle: segment count and approximate audio length from segment end times.
  static func librarySubtitle(for session: LectureSession) -> String {
    let n = session.segments.count
    let end = session.segments.map(\.endTime).max() ?? 0
    let dur = DurationFormatting.compact(end)
    if n == 0 {
      return "No segments · \(dur)"
    }
    return "\(n) segment\(n == 1 ? "" : "s") · \(dur)"
  }

  /// Short label for the Whisper model id shown in library subtitles.
  static func displayModelName(_ raw: String) -> String {
    SpeechModelDisplay.compactName(for: raw)
  }

}
