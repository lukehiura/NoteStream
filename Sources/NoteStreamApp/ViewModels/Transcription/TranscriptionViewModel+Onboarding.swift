import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func showOnboardingIfNeeded() {
    guard !onboardingCompleted else { return }
    showingOnboarding = true
  }

  func finishOnboarding() {
    onboardingCompleted = true
    showingOnboarding = false
  }

  func skipOnboarding() {
    onboardingCompleted = true
    showingOnboarding = false
  }

  func runTenSecondTestRecording() {
    startRecording()

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 10_000_000_000)

      if self.liveCaptureShowsRecordingChrome {
        self.stopAndTranscribeRecording()
      }
    }
  }
}
