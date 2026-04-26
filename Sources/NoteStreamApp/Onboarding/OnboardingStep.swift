import Foundation

enum OnboardingStep: String, CaseIterable, Identifiable {
  case screenRecording
  case transcriptionModel
  case audioTest
  case aiNotes
  case speakerLabels
  case testRecording

  var id: String { rawValue }

  var title: String {
    switch self {
    case .screenRecording: return "Screen Recording Permission"
    case .transcriptionModel: return "Transcription Model"
    case .audioTest: return "Audio Capture Test"
    case .aiNotes: return "AI Notes"
    case .speakerLabels: return "Speaker Labels"
    case .testRecording: return "Test Recording"
    }
  }

  var subtitle: String {
    switch self {
    case .screenRecording:
      return "Required to capture system audio."
    case .transcriptionModel:
      return "Choose fast, balanced, or accurate transcription."
    case .audioTest:
      return "Verify that NoteStream receives audio frames."
    case .aiNotes:
      return "Optional summaries, titles, action items, and questions."
    case .speakerLabels:
      return "Optional Speaker 1, Speaker 2 labels after transcription."
    case .testRecording:
      return "Run a short test before using the app seriously."
    }
  }

  var icon: String {
    switch self {
    case .screenRecording: return "lock.shield"
    case .transcriptionModel: return "waveform"
    case .audioTest: return "dot.radiowaves.left.and.right"
    case .aiNotes: return "sparkles"
    case .speakerLabels: return "person.2.wave.2"
    case .testRecording: return "record.circle"
    }
  }
}
