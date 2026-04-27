// swiftlint:disable file_length function_body_length
import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func startTranscription(for url: URL) {
    // Prevent concurrent transcriptions.
    if case .transcribing = uiState { return }
    if case .recording = uiState { return }
    if case .startingRecording = uiState { return }

    selectedFileName = url.lastPathComponent
    committedSegments = []
    draftSegments = []
    resetNotesStateForNewTranscript()
    askQuestionText = ""
    askAnswerMarkdown = ""
    askStatusText = nil
    showingError = false
    errorMessage = nil
    uiState = .transcribing(fileName: url.lastPathComponent)

    currentTask = Task {
      do {
        // Always prepare; transcriber will block until model is ready.
        await transcriber.prepare(model: selectedModel)

        let incoming = try await transcriber.transcribeFile(
          at: url,
          model: selectedModel,
          onProgress: { [weak self] progress in
            guard let self else { return }
            let snippet = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
              Task { @MainActor in
                // Keep UI stable: we don't stream transcript text in Phase 1,
                // but we can show an informative progress snippet.
                self.uiState = .transcribing(fileName: url.lastPathComponent)
              }
            }
          }
        )

        let coordinator = TranscriptCoordinator()
        let update = await coordinator.ingestRollingSegments(
          chunkStart: 0,
          chunkEnd: TimeInterval(incoming.last?.endTime ?? 0),
          segments: incoming,
          currentAudioTime: TimeInterval(incoming.last?.endTime ?? 0),
          boundary: .recordingStopped
        )

        let cleaned = TranscriptSanitizer.sanitize(update.committed)

        let speakerOutcome = await applySpeakerDiarizationIfEnabled(
          to: cleaned,
          audioURL: url
        )
        let finalTranscriptSegments = speakerOutcome.segments

        let notesSummary = await summarizeFinalTranscript(segments: finalTranscriptSegments)

        let defaultFileTitle = url.deletingPathExtension().lastPathComponent
        let finalTitle: String
        if autoRenameRecordingsWithAI,
          notesSummaryEnabled,
          shouldAutoReplaceImportTitle(defaultFileTitle),
          let cleaned = GeneratedTitleFormatter.sanitize(notesSummary?.title ?? "")
        {
          finalTitle = cleaned
        } else {
          finalTitle = defaultFileTitle
        }

        committedSegments = finalTranscriptSegments
        draftSegments = update.draft
        liveTranscriptSegments = finalTranscriptSegments
        notesMarkdown = notesSummary?.summaryMarkdown ?? ""
        generatedTitle = notesSummary?.title
        topicTimeline = notesSummary?.topicTimeline ?? []
        selectedFileName = finalTitle
        uiState = .completed(fileName: finalTitle)

        let session = LectureSession(
          title: finalTitle,
          sourceFileName: url.lastPathComponent,
          model: selectedModel,
          segments: finalTranscriptSegments,
          notesMarkdown: notesSummary?.summaryMarkdown,
          metadata: SessionMetadata(
            transcriptionStatus: "final_ok",
            speakerDiarizationStatus: speakerOutcome.status,
            speakerCount: speakerOutcome.speakerCount,
            speakerLabels: speakerOutcome.speakerLabels
          )
        )
        try await sessionStore.save(session)
        await reloadSessions()
      } catch is CancellationError {
        uiState = .idle
      } catch {
        let msg = String(describing: error)
        uiState = .failed(message: msg)
        errorMessage = msg
        showingError = true
      }
    }
  }

  func startRecordingStartupWatchdog(startedAt: Date) {
    recordingStartupWatchdogTask?.cancel()

    recordingStartupWatchdogTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 9_000_000_000)

      guard !Task.isCancelled else { return }

      guard case .startingRecording(let currentStartedAt) = self.uiState,
        currentStartedAt == startedAt
      else { return }

      self.startRecordingTask?.cancel()
      self.startRecordingTask = nil
      self.errorMessage =
        "Timed out starting system audio capture. Capture state was reset. Try again."
      self.showingError = true
      let failMsg = self.errorMessage ?? "Recording startup timed out."
      self.setUIState(.failed(message: failMsg), reason: "recording_start_timed_out")
      self.stopRecordingTimer()

      await self.diagnostics.error(.recorder, "recording_start_timed_out", nil, [:])

      _ = try? await self.recorder.stopRecording()

      self.recordingStartupWatchdogTask = nil
    }
  }

  func startRecording() {
    if isBusy { return }

    let optimisticStartedAt = Date()
    setUIState(
      .startingRecording(startedAt: optimisticStartedAt), reason: "recording_start_requested")
    startRecordingTimer()
    startRecordingStartupWatchdog(startedAt: optimisticStartedAt)

    showingError = false
    errorMessage = nil
    rollingFrameCount = 0
    rollingChunkCount = 0
    rollingErrorCount = 0
    rollingLastError = nil
    lastRMS = 0
    audioHealth = .ok
    liveTranscriptSegments = []
    committedSegments = []
    draftSegments = []
    selectedSessionID = nil
    selectedFileName = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    playback.cleanup()

    startRecordingTask?.cancel()

    startRecordingTask = Task {
      do {
        if !ScreenRecordingPermission.hasPermission() {
          let granted = await ScreenRecordingPermission.request()
          if Task.isCancelled { return }
          if !granted {
            showingPermissionPanel = true
            recordingStartupWatchdogTask?.cancel()
            recordingStartupWatchdogTask = nil
            setUIState(.ready(selectedModel), reason: "permission_denied")
            stopRecordingTimer()
            return
          }
        }

        let sessionId = UUID()
        let folder = try await sessionStore.sessionFolderURL(id: sessionId)
        let audioURL = folder.appendingPathComponent("audio.caf")
        currentSessionDiagnosticsURL = folder.appendingPathComponent("diagnostics.jsonl")

        let rec = try await Task.detached(priority: .userInitiated) { [recorder] in
          try await recorder.startRecording(outputURL: audioURL)
        }.value

        if Task.isCancelled {
          activeRecording = RecordingSession(
            id: sessionId,
            startedAt: rec.startedAt,
            outputURL: audioURL
          )
          await abandonInFlightRecordingStartAfterCancellation()
          return
        }

        activeRecording = RecordingSession(
          id: sessionId,
          startedAt: rec.startedAt,
          outputURL: audioURL
        )

        setUIState(
          .recording(startedAt: rec.startedAt),
          reason: "recording_started",
          metadata: ["sessionID": sessionId.uuidString]
        )
        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = nil
        startRecordingTimer()
        await startLiveSpeakerDiarizationIfNeededAsync()
        maybeUpdateLiveNotes()

        let stream = await recorder.audioFrames()
        let pipeline = RollingTranscriptionPipeline(
          transcriber: transcriber,
          diagnostics: diagnostics
        )

        rollingTask?.cancel()
        rollingTask = Task {
          let meter = RMSMeter()

          let frames = AsyncThrowingStream<AudioFrame, Error> { continuation in
            let t = Task {
              for await frame in stream {
                await MainActor.run {
                  self.rollingFrameCount += 1
                  self.lastRMS = meter.rms(of: frame.samples)
                  self.scheduleLiveDiarizationFrame(frame)
                }
                continuation.yield(frame)
              }
              continuation.finish()
            }

            continuation.onTermination = { _ in
              t.cancel()
            }
          }

          let updates = await pipeline.run(
            frames: frames,
            model: selectedModel
          )

          do {
            for try await update in updates {
              await MainActor.run {
                self.rollingChunkCount += 1
                self.audioHealth = update.audioHealth
                self.mergeRollingUpdate(update)
                self.committedSegments = self.liveTranscriptSegments.filter {
                  $0.status == .committed
                }
                self.draftSegments = self.liveTranscriptSegments.filter { $0.status == .draft }
                self.maybeUpdateLiveNotes()
              }
            }
          } catch {
            await MainActor.run {
              self.rollingErrorCount += 1
              self.rollingLastError = String(describing: error)
            }
          }
        }
      } catch {
        await recoverFromRecordingStartFailure(error)
      }
    }
  }

  func recoverFromRecordingStartFailure(_ error: Error) async {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    rollingTask?.cancel()
    rollingTask = nil
    cancelLiveNotesTasks()
    await stopLiveSpeakerDiarizationAsync()
    activeRecording = nil
    let sessionLogPath = currentSessionDiagnosticsURL?.path
    currentSessionDiagnosticsURL = nil
    stopRecordingTimer()

    _ = try? await recorder.stopRecording()

    let ns = error as NSError
    var hint = ""
    if ns.domain == "NoteStream", ns.code == 13 {
      hint =
        "SCK startup exceeded the in-app timeout. Search diagnostics for recorder / SCK messages."
    }
    await diagnostics.error(
      .transcription,
      "recording_start_failed_ui",
      error,
      [
        "screenRecordingPermission": "\(ScreenRecordingPermission.hasPermission())",
        "sessionLogPath": sessionLogPath ?? "",
        "hint": hint,
      ]
    )

    let msg: String

    if ns.domain == "NoteStream", ns.code == 10 {
      msg =
        "Recording was already in progress, but the app state was out of sync. Capture has been reset. Try recording again."
    } else {
      msg = String(describing: error)
    }

    setUIState(.failed(message: msg), reason: "recording_start_failed")
    errorMessage = msg
    showingError = true
  }

  func abandonInFlightRecordingStartAfterCancellation() async {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    rollingTask?.cancel()
    rollingTask = nil
    cancelLiveNotesTasks()
    await stopLiveSpeakerDiarizationAsync()
    currentSessionDiagnosticsURL = nil
    stopRecordingTimer()

    _ = try? await recorder.stopRecording()

    activeRecording = nil

    setUIState(.ready(selectedModel), reason: "recording_start_abandoned")
  }

  func stopAndTranscribeRecording() {
    if case .startingRecording = uiState {
      startRecordingTask?.cancel()
      startRecordingTask = nil
      rollingTask?.cancel()
      rollingTask = nil
      Task {
        await abandonInFlightRecordingStartAfterCancellation()
      }
      return
    }

    guard case .recording = uiState else { return }

    // UI can be ".recording" while `activeRecording` is nil (failed/partial start). Let the user recover.
    guard let activeRecording else {
      Task {
        await diagnostics.log(
          .init(
            level: .warning, category: "transcription", message: "stop_with_no_active_recording",
            metadata: ["uiState": String(describing: uiState)]))
        await MainActor.run {
          self.uiState = .ready(self.selectedModel)
          self.stopRecordingTimer()
        }
        // Best effort: if SCK is wedged, try to clear recorder state.
        _ = try? await recorder.stopRecording()
      }
      return
    }

    cancelLiveNotesTasks()
    liveNotesStatusText = nil
    liveNotes.reset()

    let capRolling =
      liveTranscriptSegments
      .sorted { $0.startTime < $1.startTime }
      .map { segment in
        var s = segment
        s.status = .committed
        s.text = cleanDisplayText(s.text)
        return s
      }

    let rec = activeRecording
    let model = selectedModel
    let transcriber = self.transcriber
    let sessionStore = self.sessionStore
    let diag = self.diagnostics

    rollingTask?.cancel()
    rollingTask = nil
    draftSegments = []
    currentTask?.cancel()

    setUIState(
      .finalizingTranscript(fileName: rec.outputURL.lastPathComponent),
      reason: "recording_stop_requested",
      metadata: ["sessionID": rec.id.uuidString]
    )

    currentTask = Task {
      do {
        cancelLiveNotesTasks()
        await self.stopLiveSpeakerDiarizationAsync()

        await diag.log(
          .init(
            level: .info,
            category: "transcription",
            message: "rolling_snapshot_captured",
            metadata: ["segments": "\(capRolling.count)"]
          ))
        await diag.log(
          .init(
            level: .info, category: "transcription", message: "final_transcription_started",
            metadata: ["model": model]))
        await diag.log(
          .init(
            level: .info, category: "transcription", message: "stop_and_transcribe_begin",
            metadata: [
              "session": rec.id.uuidString,
              "audio": rec.outputURL.lastPathComponent,
            ]))

        let audioURL: URL
        do {
          // Never block the main actor on SCK / file IO / Whisper.
          audioURL = try await Task.detached(priority: .userInitiated) { [recorder] in
            try await recorder.stopRecording()
          }.value
        } catch {
          await diag.log(
            .init(
              level: .error, category: "transcription", message: "recorder_stop_failed",
              metadata: ["error": String(describing: error)]))
          throw error
        }

        do {
          try self.validateAudioFile(audioURL)
        } catch {
          // Still save a session stub so the user can see failure + has the folder.
          let failedSession = LectureSession(
            id: rec.id,
            title: SessionUIFormatting.recordingSessionTitle(startedAt: rec.startedAt),
            createdAt: rec.startedAt,
            sourceFileName: nil,
            sourceAudioRelativePath: "audio.caf",
            model: model,
            segments: [],
            metadata: SessionMetadata(
              createdAt: rec.startedAt,
              updatedAt: Date(),
              transcriptionStatus: "failed",
              errorMessage: String(describing: error),
              speakerDiarizationStatus: nil,
              speakerCount: nil,
              speakerLabels: [:]
            )
          )
          try? await sessionStore.save(failedSession)
          await reloadSessions()
          throw error
        }

        // Run a full-file pass for correctness. Rolling transcript is preview-only.
        await Task.detached(priority: .userInitiated) { [transcriber, model] in
          await transcriber.prepare(model: model)
        }.value

        // swiftlint:disable closure_parameter_position
        let finalSegments: [TranscriptSegment] = try await Task.detached(priority: .userInitiated) {
          [transcriber, model, audioURL] in
          try await transcriber.transcribeFile(
            at: audioURL,
            model: model,
            onProgress: { _ in }
          )
        }.value
        // swiftlint:enable closure_parameter_position

        let coordinator = TranscriptCoordinator()
        let update = await coordinator.ingestRollingSegments(
          chunkStart: 0,
          chunkEnd: TimeInterval(finalSegments.last?.endTime ?? 0),
          segments: finalSegments,
          currentAudioTime: TimeInterval(finalSegments.last?.endTime ?? 0),
          boundary: .recordingStopped
        )

        let cleaned = TranscriptSanitizer.sanitize(update.committed)

        let speakerOutcome = await applySpeakerDiarizationIfEnabled(
          to: cleaned,
          audioURL: audioURL
        )
        let finalTranscriptSegments = speakerOutcome.segments

        let notesSummary = await summarizeFinalTranscript(segments: finalTranscriptSegments)

        let defaultRecordingTitle = SessionUIFormatting.recordingSessionTitle(
          startedAt: rec.startedAt)
        let finalTitle = titleAfterAISummary(
          defaultTitle: defaultRecordingTitle,
          currentTitle: defaultRecordingTitle,
          createdAt: rec.startedAt,
          notesSummary: notesSummary
        )

        let status = finalTranscriptSegments.isEmpty ? "empty_final_transcript" : "final_ok"
        let statusMsg =
          finalTranscriptSegments.isEmpty ? "Final transcription produced no segments." : nil

        let retainedAudioPath = retainedAudioRelativePathAfterFinalSave()

        let session = LectureSession(
          id: rec.id,
          title: finalTitle,
          createdAt: rec.startedAt,
          sourceFileName: nil,
          sourceAudioRelativePath: retainedAudioPath,
          model: model,
          segments: finalTranscriptSegments,
          notesMarkdown: notesSummary?.summaryMarkdown,
          metadata: SessionMetadata(
            createdAt: rec.startedAt,
            updatedAt: Date(),
            transcriptionStatus: status,
            errorMessage: statusMsg,
            speakerDiarizationStatus: speakerOutcome.status,
            speakerCount: speakerOutcome.speakerCount,
            speakerLabels: speakerOutcome.speakerLabels
          )
        )
        try await sessionStore.save(session)
        await deleteAudioAfterFinalSaveIfNeeded(audioURL)

        await diag.log(
          .init(
            level: .info,
            category: "session",
            message: "session_saved",
            metadata: [
              "id": session.id.uuidString,
              "segments": "\(finalTranscriptSegments.count)",
              "status": session.metadata.transcriptionStatus ?? "",
            ]
          ))
        await reloadSessions()

        await MainActor.run {
          self.committedSegments = finalTranscriptSegments
          self.draftSegments = []
          self.liveTranscriptSegments = finalTranscriptSegments
          self.selectedSessionID = session.id
          self.selectedFileName = session.title
          self.notesMarkdown = notesSummary?.summaryMarkdown ?? ""
          self.generatedTitle = notesSummary?.title
          self.topicTimeline = notesSummary?.topicTimeline ?? []
          self.uiState = .completed(fileName: session.title)

          if retainedAudioPath == nil {
            self.playback.cleanup()
          }
        }

        self.activeRecording = nil
        self.currentSessionDiagnosticsURL = nil
        self.stopRecordingTimer()
      } catch {
        let msg = String(describing: error)
        await diag.log(
          .init(
            level: .error,
            category: "transcription",
            message: "final_transcription_failed",
            metadata: ["error": msg]
          ))

        let fallback = TranscriptSanitizer.sanitize(capRolling)

        let status = fallback.isEmpty ? "failed" : "rolling_only"
        let userMessage =
          fallback.isEmpty
          ? msg : "Final transcription failed. Saved the rolling transcript instead. Error: \(msg)"

        let failedSession = LectureSession(
          id: rec.id,
          title: SessionUIFormatting.recordingSessionTitle(startedAt: rec.startedAt),
          createdAt: rec.startedAt,
          sourceFileName: nil,
          sourceAudioRelativePath: "audio.caf",
          model: model,
          segments: fallback,
          metadata: SessionMetadata(
            createdAt: rec.startedAt,
            updatedAt: Date(),
            transcriptionStatus: status,
            errorMessage: userMessage,
            speakerDiarizationStatus: nil,
            speakerCount: nil,
            speakerLabels: [:]
          )
        )

        try? await sessionStore.save(failedSession)
        await reloadSessions()

        await MainActor.run {
          self.committedSegments = fallback
          self.draftSegments = []
          self.liveTranscriptSegments = fallback
          self.selectedSessionID = failedSession.id
          self.selectedFileName = failedSession.title

          if fallback.isEmpty {
            self.uiState = .failed(message: userMessage)
            self.errorMessage = userMessage
            self.showingError = true
          } else {
            self.uiState = .completed(fileName: failedSession.title)
          }
        }

        self.activeRecording = nil
        self.currentSessionDiagnosticsURL = nil
        self.stopRecordingTimer()
      }
    }
  }
}
