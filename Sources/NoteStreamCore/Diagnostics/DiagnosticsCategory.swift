import Foundation

public enum DiagnosticsCategory: String, Codable, Sendable, CaseIterable {
  case app
  case ui
  case model
  case recorder
  case audio
  case rolling
  case transcription
  case diarization
  case notes
  case ollama
  case persistence
  case playback
  case permissions
  case settings
}
