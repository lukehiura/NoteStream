import Foundation

public enum NotesDetailLevel: String, Codable, CaseIterable, Identifiable, Sendable {
  case brief
  case balanced
  case detailed

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .brief: return "Brief"
    case .balanced: return "Balanced"
    case .detailed: return "Detailed"
    }
  }

  public var promptInstruction: String {
    switch self {
    case .brief:
      return "Keep notes short. Prefer concise bullets. Avoid long explanations."
    case .balanced:
      return "Use a balanced level of detail. Capture the main context without over-explaining."
    case .detailed:
      return "Create detailed notes. Preserve important nuance, examples, disagreements, and context."
    }
  }
}

public enum NotesTone: String, Codable, CaseIterable, Identifiable, Sendable {
  case clean
  case meetingMinutes
  case executive
  case studyNotes
  case casual

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .clean: return "Clean"
    case .meetingMinutes: return "Meeting Minutes"
    case .executive: return "Executive"
    case .studyNotes: return "Study Notes"
    case .casual: return "Casual"
    }
  }

  public var promptInstruction: String {
    switch self {
    case .clean:
      return "Use clean, neutral, readable Markdown."
    case .meetingMinutes:
      return "Format like meeting minutes. Emphasize decisions, action items, owners, and open questions."
    case .executive:
      return "Format like an executive brief. Emphasize bottom line, risks, decisions, and next steps."
    case .studyNotes:
      return "Format like study notes. Emphasize concepts, explanations, examples, and terms."
    case .casual:
      return "Use a casual but clear style. Keep the wording natural."
    }
  }
}

public enum NotesLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
  case sameAsTranscript
  case english
  case japanese
  case spanish
  case chinese

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .sameAsTranscript: return "Same as transcript"
    case .english: return "English"
    case .japanese: return "Japanese"
    case .spanish: return "Spanish"
    case .chinese: return "Chinese"
    }
  }

  public var promptInstruction: String {
    switch self {
    case .sameAsTranscript:
      return "Write notes in the same primary language as the transcript."
    case .english:
      return "Write notes in English."
    case .japanese:
      return "Write notes in Japanese."
    case .spanish:
      return "Write notes in Spanish."
    case .chinese:
      return "Write notes in Chinese."
    }
  }
}

public struct NotesSectionPreferences: Codable, Equatable, Sendable {
  public var summary: Bool
  public var keyPoints: Bool
  public var actionItems: Bool
  public var openQuestions: Bool
  public var decisions: Bool
  public var topicTimeline: Bool
  public var speakerHighlights: Bool

  public init(
    summary: Bool = true,
    keyPoints: Bool = true,
    actionItems: Bool = true,
    openQuestions: Bool = true,
    decisions: Bool = false,
    topicTimeline: Bool = true,
    speakerHighlights: Bool = false
  ) {
    self.summary = summary
    self.keyPoints = keyPoints
    self.actionItems = actionItems
    self.openQuestions = openQuestions
    self.decisions = decisions
    self.topicTimeline = topicTimeline
    self.speakerHighlights = speakerHighlights
  }

  public static let standard = NotesSectionPreferences()
}

public struct NotesGenerationPreferences: Codable, Equatable, Sendable {
  public var detailLevel: NotesDetailLevel
  public var tone: NotesTone
  public var language: NotesLanguage
  public var sections: NotesSectionPreferences
  public var customInstructions: String
  public var liveUpdateStyle: NotesDetailLevel

  public init(
    detailLevel: NotesDetailLevel = .balanced,
    tone: NotesTone = .clean,
    language: NotesLanguage = .sameAsTranscript,
    sections: NotesSectionPreferences = .standard,
    customInstructions: String = "",
    liveUpdateStyle: NotesDetailLevel = .brief
  ) {
    self.detailLevel = detailLevel
    self.tone = tone
    self.language = language
    self.sections = sections
    self.customInstructions = customInstructions
    self.liveUpdateStyle = liveUpdateStyle
  }

  public static let standard = NotesGenerationPreferences()
}
