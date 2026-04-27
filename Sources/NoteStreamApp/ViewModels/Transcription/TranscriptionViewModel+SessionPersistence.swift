import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func clear() {
    currentTask?.cancel()
    currentTask = nil
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    startRecordingTask?.cancel()
    startRecordingTask = nil
    if case .startingRecording = uiState {
      Task { await abandonInFlightRecordingStartAfterCancellation() }
    }
    rollingTask?.cancel()
    rollingTask = nil
    selectedFileName = nil
    committedSegments = []
    draftSegments = []
    liveTranscriptSegments = []
    showingError = false
    errorMessage = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    playback.cleanup()

    if let modelStatus,
      modelStatus.model == selectedModel,
      modelStatus.state == .ready
    {
      uiState = .ready(selectedModel)
    } else {
      uiState = .idle
    }
  }

  func openSelectedSessionFolder() {
    guard let id = selectedSessionID else { return }
    Task {
      do {
        let url = try await sessionStore.sessionFolderURL(id: id)
        await MainActor.run {
          _ = NSWorkspace.shared.open(url)
        }
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func openSessionFolder(id: UUID) {
    Task {
      do {
        let url = try await sessionStore.sessionFolderURL(id: id)
        NSWorkspace.shared.open(url)
      } catch {
        errorMessage = String(describing: error)
        showingError = true
      }
    }
  }

  func openSessionTranscript(id: UUID) {
    Task {
      do {
        let folder = try await sessionStore.sessionFolderURL(id: id)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
          throw NSError(
            domain: "NoteStream", code: 41,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Transcript file not found at \(transcriptURL.lastPathComponent)."
            ])
        }
        NSWorkspace.shared.open(transcriptURL)
      } catch {
        errorMessage = String(describing: error)
        showingError = true
      }
    }
  }

  func deleteSession(id: UUID) {
    Task {
      do {
        try await sessionStore.delete(id: id)
        await reloadSessions()
        await MainActor.run {
          if selectedSessionID == id {
            selectedSessionID = nil
          }
        }
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func renameSpeaker(speakerID: String, name: String) {
    let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedName.isEmpty else { return }

    mutateAllSegmentBuckets { segment in
      var updated = segment
      if updated.speakerID == speakerID {
        updated.speakerName = cleanedName
      }
      return updated
    }

    guard let selectedSessionID else { return }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        session.segments = session.segments.map { segment in
          var updated = segment
          if updated.speakerID == speakerID {
            updated.speakerName = cleanedName
          }
          return updated
        }

        session.metadata.speakerLabels[speakerID] = cleanedName
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

  func renameSession(id: UUID, title: String) {
    let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTitle.isEmpty else { return }

    Task {
      do {
        var session = try await sessionStore.load(id: id)
        session.title = cleanedTitle
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        await MainActor.run {
          if self.selectedSessionID == id {
            self.selectedFileName = cleanedTitle
            if case .completed = self.uiState {
              self.uiState = .completed(fileName: cleanedTitle)
            }
          }
        }
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func reloadSessions() async {
    do {
      let items = try await sessionStore.list()
      sessions = items
    } catch {
      // Non-fatal; session listing isn't required for transcription to work.
    }
  }
}
