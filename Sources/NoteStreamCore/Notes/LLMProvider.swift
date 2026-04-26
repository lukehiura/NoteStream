import Foundation

public enum LLMProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case off
  case ollama
  case openAI
  case anthropic
  case openAICompatible
  case externalExecutable

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .off:
      return "Off"
    case .ollama:
      return "Local Ollama"
    case .openAI:
      return "OpenAI"
    case .anthropic:
      return "Anthropic Claude"
    case .openAICompatible:
      return "OpenAI Compatible"
    case .externalExecutable:
      return "External Executable"
    }
  }

  public var requiresAPIKey: Bool {
    switch self {
    case .openAI, .anthropic, .openAICompatible:
      return true
    case .off, .ollama, .externalExecutable:
      return false
    }
  }

  /// Whether the Settings UI should show a base URL field. (OpenAI-compatible needs a server URL; Ollama defaults to localhost.)
  public var requiresBaseURL: Bool {
    switch self {
    case .ollama, .openAICompatible:
      return true
    case .off, .openAI, .anthropic, .externalExecutable:
      return false
    }
  }
}
