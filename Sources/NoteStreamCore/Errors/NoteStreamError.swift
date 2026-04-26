import Foundation

public enum NoteStreamError: LocalizedError, Equatable {
  case noActiveRecording
  case audioFileMissing
  case diarizerNotConfigured
  case notesSummarizerNotConfigured
  case ollamaUnavailable(String)
  case invalidLLMResponse(String)
  case askRecordingUnsupported
  case missingLLMBaseURL
  case missingAnthropicAPIKey
  case utf8EncodingFailed(String)
  case httpFailure(status: Int, body: String)

  public var errorDescription: String? {
    switch self {
    case .noActiveRecording:
      return "There is no active recording to use for this action."
    case .audioFileMissing:
      return "The session audio file is missing on disk."
    case .diarizerNotConfigured:
      return "Configure a speaker diarizer executable before running diarization."
    case .notesSummarizerNotConfigured:
      return "Configure an AI notes provider before generating notes."
    case .ollamaUnavailable(let detail):
      return "Ollama is not reachable or returned an error: \(detail)"
    case .invalidLLMResponse(let detail):
      return "The model returned an unexpected response: \(detail)"
    case .askRecordingUnsupported:
      return "Ask this Recording is not available for the current provider."
    case .missingLLMBaseURL:
      return "A base URL is required for this provider."
    case .missingAnthropicAPIKey:
      return "An Anthropic API key is required."
    case .utf8EncodingFailed(let context):
      return "Failed to encode text as UTF-8 (\(context))."
    case .httpFailure(let status, let body):
      let trimmed = body.prefix(500)
      return "Request failed with HTTP \(status): \(trimmed)"
    }
  }
}
