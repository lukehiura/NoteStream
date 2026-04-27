import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func clearExternalToolPaths() {
    speakerDiarizerCommandPath = ""
    notesSummarizerCommandPath = ""
  }

  func resetExternalToolIntegrations() {
    clearExternalToolPaths()
  }

  func testSpeakerDiarizerOnSelectedSession() {
    guard let selectedSessionID else {
      speakerDiarizationStatusText = "Select a saved session first."
      return
    }

    guard realSpeakerDiarizationIsReady else {
      speakerDiarizationStatusText = realSpeakerDiarizationSetupText
      return
    }

    Task {
      do {
        let session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "Selected session has no saved audio."
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

        guard let speakerDiarizer else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "No diarizer configured."
          }
          return
        }

        await MainActor.run {
          self.speakerDiarizationStatusText = "Testing speaker diarizer…"
        }

        let result = try await speakerDiarizer.diarize(
          audioURL: audioURL,
          expectedSpeakerCount: expectedSpeakerCount
        )

        await MainActor.run {
          self.speakerDiarizationStatusText =
            "Diarizer OK: \(result.speakerCount) speakers, \(result.turns.count) turns."
        }
      } catch {
        await MainActor.run {
          self.speakerDiarizationStatusText = "Diarizer test failed: \(String(describing: error))"
        }
      }
    }
  }

  func testNotesSummarizer() {
    guard let notesSummarizer else {
      notesStatusText = "No notes summarizer configured."
      return
    }

    let sampleTranscript = """
      [00:00] Speaker 1: Today we discussed housing supply, land value taxes, and Austin rents.
      [00:10] Speaker 2: Austin allowed more building, and rents dropped despite migration.
      [00:20] Speaker 1: The open question is whether New York can do the same with land constraints.
      """

    notesStatusText = "Testing notes summarizer…"

    let prefs = notesGenerationPreferences
    Task {
      do {
        let result = try await notesSummarizer.summarize(
          NotesSummarizationRequest(
            transcriptMarkdown: sampleTranscript,
            previousNotesMarkdown: nil,
            mode: .final,
            preferences: prefs
          )
        )

        await MainActor.run {
          self.generatedTitle = result.title
          self.notesMarkdown = result.summaryMarkdown
          self.notesStatusText = "Summarizer OK: \(result.title)"
        }
      } catch {
        await MainActor.run {
          self.notesStatusText = "Summarizer test failed: \(String(describing: error))"
        }
      }
    }
  }

  func loadPlaybackForSelectedSession() {
    guard let selectedSessionID else { return }

    Task {
      do {
        let session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.playback.cleanup()
          }
          return
        }

        let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
        let audioURL = folder.appendingPathComponent(relativeAudio)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
          await MainActor.run {
            self.playback.cleanup()
          }
          return
        }

        await MainActor.run {
          self.playback.load(url: audioURL)
        }
      } catch {
        await MainActor.run {
          self.playback.cleanup()
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func seekPlayback(to seconds: TimeInterval) {
    playback.seek(to: seconds)
  }
}
