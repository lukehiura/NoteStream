import Foundation
import NoteStreamCore

/// LLM-backed Q&A over a transcript (Ollama chat, OpenAI chat completions, Anthropic Messages).
public final class HTTPRecordingQuestionAnswerer: RecordingQuestionAnswering, @unchecked Sendable {
  private let config: HTTPNotesSummarizerConfig
  private let llmClient: LLMHTTPClient

  public init(
    config: HTTPNotesSummarizerConfig,
    urlSession: URLSession = .shared
  ) {
    self.config = config
    self.llmClient = LLMHTTPClient(
      urlSession: urlSession,
      diagnostics: NoopDiagnosticsLogger(),
      category: "ask_recording"
    )
  }

  public func answer(_ request: RecordingQuestionRequest) async throws -> RecordingQuestionAnswer {
    switch config.provider {
    case .ollama:
      return try await answerWithOllama(request)
    case .openAI, .openAICompatible:
      return try await answerWithOpenAICompatible(request)
    case .anthropic:
      return try await answerWithAnthropic(request)
    case .off, .externalExecutable:
      throw NoteStreamError.askRecordingUnsupported
    }
  }

  private func prompt(_ request: RecordingQuestionRequest) -> String {
    """
    Answer the user's question using only the transcript and notes below.

    Rules:
    - Do not invent facts.
    - If the transcript does not contain the answer, say so.
    - Use speaker labels when useful.
    - Mention timestamps when relevant.
    - Keep the answer concise.

    Notes:
    \(request.notesMarkdown ?? "(none)")

    Transcript:
    \(request.transcriptMarkdown)

    Question:
    \(request.question)
    """
  }

  private func answerWithOllama(_ request: RecordingQuestionRequest) async throws
    -> RecordingQuestionAnswer
  {
    let url = try LLMEndpointBuilder.ollamaChat(baseURL: config.baseURL)

    let body: [String: Any] = [
      "model": config.model,
      "stream": false,
      "messages": [
        [
          "role": "system",
          "content": "You answer questions about a recorded transcript. Use only provided context.",
        ],
        [
          "role": "user",
          "content": prompt(request),
        ],
      ],
    ]

    let data = try await llmClient.postJSON(url: url, headers: [:], body: body)
    let content = try LLMResponseExtractor.ollamaMessageContent(from: data)

    return RecordingQuestionAnswer(answerMarkdown: content)
  }

  private func answerWithOpenAICompatible(_ request: RecordingQuestionRequest) async throws
    -> RecordingQuestionAnswer
  {
    let url = try LLMEndpointBuilder.openAICompatibleChat(
      provider: config.provider,
      baseURL: config.baseURL
    )

    var headers: [String: String] = [:]
    if let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    {
      headers["Authorization"] = "Bearer \(apiKey)"
    }

    let body: [String: Any] = [
      "model": config.model,
      "messages": [
        [
          "role": "system",
          "content": "You answer questions about a recorded transcript. Use only provided context.",
        ],
        [
          "role": "user",
          "content": prompt(request),
        ],
      ],
      "temperature": 0.2,
    ]

    let data = try await llmClient.postJSON(url: url, headers: headers, body: body)
    let content = try LLMResponseExtractor.openAIChatContent(from: data)

    return RecordingQuestionAnswer(answerMarkdown: content)
  }

  private func answerWithAnthropic(_ request: RecordingQuestionRequest) async throws
    -> RecordingQuestionAnswer
  {
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw NoteStreamError.missingAnthropicAPIKey
    }

    let url = try LLMEndpointBuilder.anthropicMessages()

    let body: [String: Any] = [
      "model": config.model,
      "max_tokens": 1200,
      "system": "You answer questions about a recorded transcript. Use only provided context.",
      "messages": [
        [
          "role": "user",
          "content": prompt(request),
        ]
      ],
    ]

    let data = try await llmClient.postJSON(
      url: url,
      headers: [
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      ],
      body: body
    )

    let text = try LLMResponseExtractor.anthropicText(from: data)

    return RecordingQuestionAnswer(answerMarkdown: text)
  }
}
