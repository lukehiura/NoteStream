import Foundation
import NoteStreamCore

enum NotesFormatPreset: String, CaseIterable, Identifiable {
  case balanced
  case meeting
  case lecture
  case executive
  case study
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .balanced: return "Balanced"
    case .meeting: return "Meeting"
    case .lecture: return "Lecture"
    case .executive: return "Executive"
    case .study: return "Study"
    case .custom: return "Custom"
    }
  }

  var icon: String {
    switch self {
    case .balanced: return "slider.horizontal.3"
    case .meeting: return "person.3"
    case .lecture: return "book.closed"
    case .executive: return "briefcase"
    case .study: return "graduationcap"
    case .custom: return "wand.and.stars"
    }
  }

  var description: String {
    switch self {
    case .balanced:
      return "General summaries with key points, action items, questions, and topic timeline."
    case .meeting:
      return "Focuses on decisions, action items, owners, risks, and open questions."
    case .lecture:
      return "Focuses on concepts, explanations, examples, and topic flow."
    case .executive:
      return "Short decision-oriented brief with risks and next steps."
    case .study:
      return "Detailed study notes with definitions, examples, and takeaways."
    case .custom:
      return "Use your manually selected sections and instructions."
    }
  }
}
