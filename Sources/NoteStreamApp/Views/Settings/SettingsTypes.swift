import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case transcription
  case speakers
  case aiNotes
  case appearance

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .transcription: return "Transcription"
    case .speakers: return "Speakers"
    case .aiNotes: return "AI Notes"
    case .appearance: return "Appearance"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .transcription: return "waveform"
    case .speakers: return "person.2.wave.2"
    case .aiNotes: return "sparkles"
    case .appearance: return "paintbrush"
    }
  }
}
