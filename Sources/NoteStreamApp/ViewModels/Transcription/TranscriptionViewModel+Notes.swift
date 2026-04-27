import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func sanitizedGeneratedTitle(_ raw: String, maxLength: Int = 72) -> String? {
    GeneratedTitleFormatter.sanitize(raw, maxLength: maxLength)
  }

  func titleAfterAISummary(
    defaultTitle: String,
    currentTitle: String,
    createdAt: Date,
    notesSummary: NotesSummary?
  ) -> String {
    guard autoRenameRecordingsWithAI else { return currentTitle }
    guard notesSummaryEnabled else { return currentTitle }
    guard shouldAutoReplaceTitle(currentTitle, createdAt: createdAt) else { return currentTitle }
    guard let raw = notesSummary?.title else { return currentTitle }
    guard let cleaned = sanitizedGeneratedTitle(raw) else { return currentTitle }

    let lower = cleaned.lowercased()
    if lower == "untitled recording" || lower == "summary" {
      return currentTitle
    }

    return cleaned
  }

  func shouldAutoReplaceTitle(_ title: String, createdAt: Date) -> Bool {
    let defaultTitle = SessionUIFormatting.recordingSessionTitle(startedAt: createdAt)
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)

    if cleaned.isEmpty { return true }
    if cleaned == defaultTitle { return true }
    if cleaned.hasPrefix("Apr ") || cleaned.hasPrefix("May ") || cleaned.hasPrefix("Jun ") {
      return true
    }
    if cleaned.hasPrefix("Recording ") { return true }

    return false
  }

  func shouldAutoReplaceImportTitle(_ fileStem: String) -> Bool {
    let s = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return true }
    if s.lowercased() == "untitled" { return true }
    if s.lowercased() == "audio" { return true }
    return false
  }

  func retainedAudioRelativePathAfterFinalSave() -> String? {
    deleteAudioAfterTranscription ? nil : "audio.caf"
  }

  func deleteAudioAfterFinalSaveIfNeeded(_ audioURL: URL) async {
    guard deleteAudioAfterTranscription else { return }

    do {
      try FileManager.default.removeItem(at: audioURL)

      await diagnostics.log(
        .init(
          level: .info,
          category: "session",
          message: "audio_deleted_after_transcription",
          metadata: ["audio": audioURL.lastPathComponent]
        ))

      playback.cleanup()
    } catch {
      await diagnostics.log(
        .init(
          level: .warning,
          category: "session",
          message: "audio_delete_failed_after_transcription",
          metadata: [
            "audio": audioURL.lastPathComponent,
            "error": String(describing: error),
          ]
        ))
    }
  }

  func openAINotesSettings() {
    preferredSettingsSectionRaw = "aiNotes"
    showingSettingsPanel = true
  }

  func enableAINotes() {
    if llmProvider == .off {
      llmProvider = .ollama
    }

    notesSummaryEnabled = true
    rebuildNotesSummarizer()

    notesStatusText = "AI notes enabled. Generate notes now or finish a recording."
  }

  func askCurrentRecording() {
    let question = askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return }

    guard let answerer = questionAnswerer else {
      askStatusText = "Choose an LLM provider before asking questions."
      return
    }

    let transcript = TranscriptContextBuilder.markdown(from: allSegments)
    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      askStatusText = "No transcript available."
      return
    }

    isAnsweringQuestion = true
    askStatusText = "Answering…"

    Task {
      do {
        let answer = try await answerer.answer(
          RecordingQuestionRequest(
            transcriptMarkdown: transcript,
            notesMarkdown: notesMarkdown.isEmpty ? nil : notesMarkdown,
            question: question
          )
        )

        await MainActor.run {
          self.askAnswerMarkdown = answer.answerMarkdown
          self.askStatusText = "Answered"
          self.isAnsweringQuestion = false
        }
      } catch {
        await MainActor.run {
          self.askStatusText = "Ask failed: \(String(describing: error))"
          self.isAnsweringQuestion = false
        }
      }
    }
  }

  func regenerateNotesForSelectedSession() {
    guard let selectedSessionID else {
      notesStatusText = "Select a saved session first."
      return
    }

    guard notesSummaryEnabled else {
      notesStatusText = "Notes summary is off."
      return
    }

    guard notesSummarizer != nil else {
      notesStatusText = "Notes summarizer is not configured."
      return
    }

    guard !allSegments.isEmpty else {
      notesStatusText = "No transcript is available to summarize."
      return
    }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        guard !session.segments.isEmpty else {
          await MainActor.run {
            self.notesStatusText = "Selected session has no transcript to summarize."
          }
          return
        }

        await MainActor.run {
          self.notesStatusText = "Regenerating notes…"
        }

        guard
          let notesSummary = await summarizeFinalTranscript(
            segments: session.segments,
            publishNoteFieldsToUI: false
          )
        else {
          await MainActor.run {
            if self.notesStatusText == "Regenerating notes…"
              || self.notesStatusText == "Generating notes…"
            {
              self.notesStatusText = "Notes regeneration did not return a summary."
            }
          }
          return
        }

        session.notesMarkdown = notesSummary.summaryMarkdown

        let renamedTitle = titleAfterAISummary(
          defaultTitle: SessionUIFormatting.recordingSessionTitle(startedAt: session.createdAt),
          currentTitle: session.title,
          createdAt: session.createdAt,
          notesSummary: notesSummary
        )
        session.title = renamedTitle

        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        let titleForUI = session.title

        await MainActor.run {
          self.notesMarkdown = notesSummary.summaryMarkdown
          self.generatedTitle = notesSummary.title
          self.topicTimeline = notesSummary.topicTimeline ?? []
          self.selectedFileName = titleForUI
          self.notesStatusText = "Notes regenerated."
          self.uiState = .completed(fileName: titleForUI)
        }
      } catch {
        await MainActor.run {
          self.notesStatusText = "Notes regeneration failed."
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func updateSegmentText(segmentID: UUID, text: String) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

    mutateAllSegmentBuckets { segment in
      var updated = segment
      if updated.id == segmentID {
        updated.text = cleaned
      }
      return updated
    }

    persistCurrentTranscriptEdits()
  }

  func deleteSegment(segmentID: UUID) {
    committedSegments.removeAll { $0.id == segmentID }
    draftSegments.removeAll { $0.id == segmentID }
    liveTranscriptSegments.removeAll { $0.id == segmentID }

    persistCurrentTranscriptEdits()
  }

  func mergeSegmentWithPrevious(segmentID: UUID) {
    var sorted = allSegments.sorted { $0.startTime < $1.startTime }
    guard let index = sorted.firstIndex(where: { $0.id == segmentID }),
      index > 0
    else { return }

    let previous = sorted[index - 1]
    let current = sorted[index]

    let combinedText = [previous.text, current.text]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let merged = TranscriptSegment(
      id: previous.id,
      startTime: previous.startTime,
      endTime: max(previous.endTime, current.endTime),
      text: combinedText,
      status: previous.status,
      confidence: previous.confidence,
      speakerID: previous.speakerID ?? current.speakerID,
      speakerName: previous.speakerName ?? current.speakerName
    )

    sorted[index - 1] = merged
    sorted.remove(at: index)

    committedSegments = sorted.filter { $0.status == .committed }
    draftSegments = sorted.filter { $0.status == .draft }
    liveTranscriptSegments = sorted

    persistCurrentTranscriptEdits()
  }

  func splitSegment(segmentID: UUID, atCharacterOffset offset: Int) {
    let sorted = TranscriptSegmentEditor.split(
      segments: allSegments,
      segmentID: segmentID,
      atCharacterOffset: offset
    )

    committedSegments = sorted.filter { $0.status == .committed }
    draftSegments = sorted.filter { $0.status == .draft }
    liveTranscriptSegments = sorted

    persistCurrentTranscriptEdits()
  }

  func persistCurrentTranscriptEdits() {
    guard let selectedSessionID else { return }

    let segments = allSegments.sorted { $0.startTime < $1.startTime }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)
        session.segments = segments
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func loadSession(id: UUID) {
    Task {
      do {
        let session = try await sessionStore.load(id: id)
        let labels = session.metadata.speakerLabels
        let mergedSegments = session.segments
          .sorted { $0.startTime < $1.startTime }
          .map { seg -> TranscriptSegment in
            var s = seg
            if let sid = s.speakerID, s.speakerName == nil, let name = labels[sid] {
              s.speakerName = name
            }
            return s
          }
        await MainActor.run {
          selectedSessionID = session.id
          selectedFileName = session.sourceFileName ?? session.title
          committedSegments = mergedSegments
          draftSegments = []
          liveTranscriptSegments = []
          let loadedNotes = session.notesMarkdown ?? ""
          notesMarkdown = loadedNotes
          topicTimeline = []
          askQuestionText = ""
          askAnswerMarkdown = ""
          askStatusText = nil
          generatedTitle = nil
          notesStatusText =
            loadedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : "Saved notes"
          uiState = .completed(fileName: session.title)
        }
        loadPlaybackForSelectedSession()
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func diarizeSelectedSession() {
    guard let selectedSessionID else { return }

    #if DEBUG
      let allowDebugOnlyDiarization = isUsingDebugSpeakerLabels && speakerDiarizer != nil
    #else
      let allowDebugOnlyDiarization = false
    #endif

    guard realSpeakerDiarizationIsReady || allowDebugOnlyDiarization else {
      speakerDiarizationStatusText = realSpeakerDiarizationSetupText
      return
    }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "No saved audio file for this session."
          }
          return
        }

        let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
        let audioURL = folder.appendingPathComponent(relativeAudio)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "Audio file not found."
          }
          return
        }

        let outcome = await applySpeakerDiarizationIfEnabled(
          to: session.segments,
          audioURL: audioURL
        )

        session.segments = outcome.segments
        session.metadata.speakerDiarizationStatus = outcome.status
        session.metadata.speakerCount = outcome.speakerCount
        session.metadata.speakerLabels = outcome.speakerLabels
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        let sorted = outcome.segments.sorted { $0.startTime < $1.startTime }
        await MainActor.run {
          self.committedSegments = sorted
          self.draftSegments = []
          self.liveTranscriptSegments = sorted
        }
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func startNew() {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    startRecordingTask?.cancel()
    startRecordingTask = nil
    if case .startingRecording = uiState {
      Task { await abandonInFlightRecordingStartAfterCancellation() }
    }
    rollingTask?.cancel()
    rollingTask = nil
    selectedSessionID = nil
    selectedFileName = nil
    committedSegments = []
    draftSegments = []
    liveTranscriptSegments = []
    audioHealth = .ok
    rollingFrameCount = 0
    rollingChunkCount = 0
    rollingErrorCount = 0
    rollingLastError = nil
    lastRMS = 0
    showingError = false
    errorMessage = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    askQuestionText = ""
    askAnswerMarkdown = ""
    askStatusText = nil
    playback.cleanup()
    prepareSelectedModelIfNeeded(force: false)
  }

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [
      UTType.wav,
      UTType.mp3,
      UTType.mpeg4Audio,
      UTType(filenameExtension: "m4a") ?? .audio,
      UTType(filenameExtension: "flac") ?? .audio,
      .audio,
    ]

    if panel.runModal() == .OK, let url = panel.url {
      startTranscription(for: url)
    }
  }
}
