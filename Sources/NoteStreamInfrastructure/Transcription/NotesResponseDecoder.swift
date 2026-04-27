import Foundation
import NoteStreamCore

enum NotesResponseDecoder {
  static func decode(_ text: String) throws -> NotesSummary {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("```") {
      s.removeFirst(3)
      if let newline = s.firstIndex(of: "\n") {
        s = String(s[s.index(after: newline)...])
      }
      s = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if s.hasSuffix("```") {
        s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    guard let data = s.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 91,
        userInfo: [
          NSLocalizedDescriptionKey: "LLM response was not UTF-8."
        ])
    }

    return try JSONDecoder().decode(NotesSummary.self, from: data)
  }
}
