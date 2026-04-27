import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func checkForRecoverableRecordings() {
    Task {
      do {
        let files = try await sessionStore.recoverableAudioFiles()
        await MainActor.run {
          self.recoverableAudioFiles = files
          self.showingRecoveryPanel = !files.isEmpty
        }
      } catch {
        // Non-fatal.
      }
    }
  }

  func recoverRecording(at url: URL) {
    startTranscription(for: url)
  }
}
