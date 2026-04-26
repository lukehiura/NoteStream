import Foundation
import NoteStreamCore

struct ExportedTranscript: Codable {
  let title: String
  let segments: [TranscriptSegment]
  let notesMarkdown: String
}
