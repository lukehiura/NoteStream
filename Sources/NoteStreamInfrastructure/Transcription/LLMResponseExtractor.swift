import Foundation
import NoteStreamCore

enum LLMResponseExtractor {
  static func ollamaMessageContent(from data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message = root?["message"] as? [String: Any]

    guard let content = message?["content"] as? String else {
      throw NoteStreamError.invalidLLMResponse("Ollama response did not contain message.content.")
    }

    return content
  }

  static func openAIChatContent(from data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let choices = root?["choices"] as? [[String: Any]]
    let message = choices?.first?["message"] as? [String: Any]

    guard let content = message?["content"] as? String else {
      throw NoteStreamError.invalidLLMResponse("OpenAI response did not contain message.content.")
    }

    return content
  }

  static func openAIResponsesText(from data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    guard let output = root?["output"] as? [[String: Any]] else {
      throw NoteStreamError.invalidLLMResponse("OpenAI Responses output was missing.")
    }

    var parts: [String] = []

    for item in output {
      guard let content = item["content"] as? [[String: Any]] else {
        continue
      }

      for block in content {
        if let text = block["text"] as? String {
          parts.append(text)
        }
      }
    }

    let joined = parts.joined(separator: "\n")

    guard !joined.isEmpty else {
      throw NoteStreamError.invalidLLMResponse("OpenAI Responses text was empty.")
    }

    return joined
  }

  /// Tries OpenAI Responses `output` first, then Chat Completions `choices[0].message.content`.
  static func openAINotesText(from data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let text = responsesJoinedText(from: root), !text.isEmpty {
      return text
    }
    if let choices = root?["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any],
      let content = message["content"] as? String,
      !content.isEmpty
    {
      return content
    }
    throw NoteStreamError.invalidLLMResponse("OpenAI response did not contain usable JSON text.")
  }

  private static func responsesJoinedText(from root: [String: Any]?) -> String? {
    guard let root, let output = root["output"] as? [[String: Any]] else { return nil }
    var parts: [String] = []
    for item in output {
      guard let content = item["content"] as? [[String: Any]] else { continue }
      for block in content {
        if let t = block["text"] as? String {
          parts.append(t)
        }
      }
    }
    let joined = parts.joined(separator: "\n")
    return joined.isEmpty ? nil : joined
  }

  static func anthropicText(from data: Data) throws -> String {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let contentBlocks = root?["content"] as? [[String: Any]]

    let text =
      contentBlocks?
      .compactMap { $0["text"] as? String }
      .joined(separator: "\n") ?? ""

    guard !text.isEmpty else {
      throw NoteStreamError.invalidLLMResponse("Anthropic response did not contain text.")
    }

    return text
  }
}
