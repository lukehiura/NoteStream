import Foundation
import NoteStreamCore
import Observation

@MainActor
@Observable
final class LiveNotesCoordinator {
  struct UpdateContext: Sendable {
    var isRecording: Bool
    var liveNotesEnabled: Bool
    var notesSummaryEnabled: Bool
    var summarizer: (any NotesSummarizing)?
    var committedSegments: [TranscriptSegment]
    var previousNotesMarkdown: String
    var intervalMinutes: Int
    var minimumCharacters: Int
    var preferences: NotesGenerationPreferences
    var shouldChunk: Bool
  }

  var isGenerating: Bool = false
  var lastUpdatedAt: Date?
  var statusText: String?

  private var task: Task<Void, Never>?
  private var lastUpdateAtAudioTime: TimeInterval = 0
  private var lastSummarizedSegmentEndTime: TimeInterval = 0

  var onNotesUpdated: ((NotesSummary, _ latestEnd: TimeInterval) -> Void)?
  var onError: ((Error) -> Void)?

  func reset() {
    task?.cancel()
    task = nil
    isGenerating = false
    lastUpdatedAt = nil
    statusText = nil
    lastUpdateAtAudioTime = 0
    lastSummarizedSegmentEndTime = 0
  }

  func cancel() {
    task?.cancel()
    task = nil
    isGenerating = false
  }

  func updateIfNeeded(force: Bool, context: UpdateContext) {
    guard context.isRecording,
      context.liveNotesEnabled,
      context.notesSummaryEnabled,
      task == nil,
      let summarizer = context.summarizer
    else { return }

    let committed =
      context.committedSegments
      .filter { $0.status == .committed }
      .sorted { $0.startTime < $1.startTime }

    guard let latestEnd = committed.map(\.endTime).max() else {
      statusText = "Waiting for transcript…"
      return
    }

    if context.shouldChunk, !force {
      statusText = "Live notes paused; transcript is long. Final notes run after Stop & Transcribe."
      return
    }

    if !force {
      let intervalSeconds = TimeInterval(context.intervalMinutes * 60)
      guard latestEnd - lastUpdateAtAudioTime >= intervalSeconds else {
        return
      }
    }

    let startAfter: TimeInterval = force ? 0 : lastSummarizedSegmentEndTime
    let newText = TranscriptContextBuilder.markdown(
      from: committed,
      startingAfter: startAfter
    )

    guard newText.count >= context.minimumCharacters || force else {
      statusText = "Waiting for \(context.minimumCharacters)+ new transcript characters…"
      return
    }

    isGenerating = true
    statusText = "Updating live notes…"

    let prefs = context.preferences
    let previousNotes = context.previousNotesMarkdown
    task = Task { [weak self, summarizer, newText, previousNotes, prefs, latestEnd] in
      guard let self else { return }
      do {
        let result = try await summarizer.summarize(
          NotesSummarizationRequest(
            transcriptMarkdown: newText,
            previousNotesMarkdown: previousNotes.isEmpty ? nil : previousNotes,
            mode: .liveUpdate,
            preferences: prefs
          )
        )

        await MainActor.run {
          self.statusText = "Live notes updated"
          self.lastUpdatedAt = Date()
          self.lastSummarizedSegmentEndTime = latestEnd
          self.lastUpdateAtAudioTime = latestEnd
          self.isGenerating = false
          self.task = nil
          self.onNotesUpdated?(result, latestEnd)
        }
      } catch {
        await MainActor.run {
          self.statusText = "Live notes failed"
          self.isGenerating = false
          self.task = nil
          self.onError?(error)
        }
      }
    }
  }

  var canRefreshNow: Bool {
    !isGenerating && task == nil
  }
}
