import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  var allSegments: [TranscriptSegment] {
    if case .recording = uiState {
      return liveTranscriptSegments.sorted { $0.startTime < $1.startTime }
    }
    if case .startingRecording = uiState {
      return liveTranscriptSegments.sorted { $0.startTime < $1.startTime }
    }
    return (committedSegments + draftSegments).sorted { $0.startTime < $1.startTime }
  }

  var transcriptMarkdown: String {
    TranscriptMarkdownFormatter.markdown(from: allSegments)
  }

  var transcriptPlainText: String {
    allSegments
      .map { seg in
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if let sp = seg.speakerName ?? seg.speakerID, !sp.isEmpty {
          return "\(sp): \(text)"
        }
        return text
      }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  func mergeRollingUpdate(_ update: TranscriptUpdate) {
    var mergedByKey: [String: TranscriptSegment] = [:]

    for segment in liveTranscriptSegments {
      mergedByKey[segmentKey(segment)] = segment
    }

    for segment in update.committed + update.draft {
      let cleanedText = cleanDisplayText(segment.text)
      guard !cleanedText.isEmpty else { continue }
      var cleaned = segment
      cleaned.text = cleanedText
      let key = segmentKey(cleaned)

      if let existing = mergedByKey[key] {
        if existing.status == .draft && cleaned.status == .committed {
          mergedByKey[key] = cleaned
        }
      } else {
        mergedByKey[key] = cleaned
      }
    }

    liveTranscriptSegments = mergedByKey.values.sorted { $0.startTime < $1.startTime }
    maybeUpdateLiveNotes()
  }

  func resetNotesStateForNewTranscript() {
    cancelLiveNotesTasks()
    notesMarkdown = ""
    topicTimeline = []
    generatedTitle = nil
    notesStatusText = nil
    liveNotesStatusText = nil
    liveNotes.reset()
  }

  func segmentKey(_ segment: TranscriptSegment) -> String {
    let start = Int((segment.startTime * 10).rounded())
    let end = Int((segment.endTime * 10).rounded())
    return "\(start)-\(end)"
  }

  func cleanDisplayText(_ text: String) -> String {
    TranscriptSanitizer.cleanWhisperText(text)
      .replacingOccurrences(of: "<|startoftranscript|>", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
