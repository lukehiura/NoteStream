import Foundation
import NoteStreamCore

enum LLMEndpointBuilder {
  static func ollamaChat(baseURL: URL?) throws -> URL {
    guard let base = baseURL ?? URL(string: "http://localhost:11434") else {
      throw NoteStreamError.missingLLMBaseURL
    }

    return
      base
      .appendingPathComponent("api")
      .appendingPathComponent("chat")
  }

  static func openAIResponses() throws -> URL {
    guard let url = URL(string: "https://api.openai.com/v1/responses") else {
      throw NoteStreamError.missingLLMBaseURL
    }
    return url
  }

  /// OpenAI official (`provider == .openAI`) or OpenAI-compatible chat completions URL.
  static func openAICompatibleChat(
    provider: LLMProvider,
    baseURL: URL?
  ) throws -> URL {
    let base: URL
    if provider == .openAI {
      guard let openAIBase = URL(string: "https://api.openai.com/v1") else {
        throw NoteStreamError.missingLLMBaseURL
      }
      base = openAIBase
    } else if let baseURL {
      base = baseURL
    } else {
      throw NoteStreamError.missingLLMBaseURL
    }

    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
      throw NoteStreamError.missingLLMBaseURL
    }

    if components.scheme == nil {
      components.scheme = "https"
    }

    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let normalizedBasePath: String
    if basePath.isEmpty {
      normalizedBasePath = "v1"
    } else if basePath.hasSuffix("v1") {
      normalizedBasePath = basePath
    } else {
      normalizedBasePath = "\(basePath)/v1"
    }
    components.path = "/\(normalizedBasePath)/chat/completions"

    guard let url = components.url else {
      throw NoteStreamError.missingLLMBaseURL
    }

    return url
  }

  static func anthropicMessages() throws -> URL {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
      throw NoteStreamError.missingLLMBaseURL
    }
    return url
  }
}
