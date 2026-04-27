import Foundation
import NoteStreamCore

enum NotesPromptBuilder {
  static func buildPrompt(_ request: NotesSummarizationRequest) -> String {
    let prefs = request.preferences
    let sections = sectionInstruction(prefs.sections)
    let custom = customInstructionBlock(prefs.customInstructions)

    switch request.mode {
    case .final:
      return """
        Create structured notes from this transcript.

        Rules:
        - Return JSON only.
        - Do not invent facts.
        - Keep speaker labels when useful.
        - Create a short, specific title.
        - Title must be 4 to 9 words.
        - Do not include dates, file names, or generic words like "Recording" or "Transcript".
        - \(prefs.detailLevel.promptInstruction)
        - \(prefs.tone.promptInstruction)
        - \(prefs.language.promptInstruction)
        - \(sections)
        - \(topicTimelineInstruction(prefs.sections))
        - Use empty arrays when there are no action items or open questions.
        - Preserve uncertainty when the transcript is unclear.

        \(custom)

        Transcript:
        \(request.transcriptMarkdown)
        """

    case .liveUpdate:
      return """
        Update running notes from a live transcript.

        Rules:
        - Return JSON only.
        - Merge the new transcript into previous notes.
        - Do not duplicate previous points.
        - Do not invent facts.
        - Keep the notes stable. Do not rewrite everything unless needed.
        - \(prefs.liveUpdateStyle.promptInstruction)
        - \(prefs.tone.promptInstruction)
        - \(prefs.language.promptInstruction)
        - \(sections)
        - Keep live notes provisional. Prefer concise updates.
        - Preserve existing useful notes from previousNotesMarkdown.

        \(custom)

        Previous notes:
        \(request.previousNotesMarkdown ?? "(none)")

        New transcript:
        \(request.transcriptMarkdown)
        """
    }
  }

  private static func sectionInstruction(_ sections: NotesSectionPreferences) -> String {
    var enabled: [String] = []

    if sections.summary { enabled.append("Summary") }
    if sections.keyPoints { enabled.append("Key Points") }
    if sections.actionItems { enabled.append("Action Items") }
    if sections.openQuestions { enabled.append("Open Questions") }
    if sections.decisions { enabled.append("Decisions") }
    if sections.topicTimeline { enabled.append("Topic Timeline") }
    if sections.speakerHighlights { enabled.append("Speaker Highlights") }

    if enabled.isEmpty {
      return "Include a short Summary section."
    }

    return "Include these sections in summaryMarkdown: \(enabled.joined(separator: ", "))."
  }

  private static func topicTimelineInstruction(_ sections: NotesSectionPreferences) -> String {
    guard sections.topicTimeline else {
      return "Set topicTimeline to an empty array if the schema requires it."
    }

    return """
      Create topicTimeline with 5 to 12 timestamped items when enough transcript exists.
      Each topicTimeline item should include startTime in seconds, title, and optional summary.
      """
  }

  private static func customInstructionBlock(_ text: String) -> String {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return "No custom user instructions." }

    return """
      User custom instructions:
      \(cleaned)
      """
  }
}
