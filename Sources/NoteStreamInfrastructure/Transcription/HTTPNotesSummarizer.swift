import Foundation
import NoteStreamCore

public struct HTTPNotesSummarizerConfig: Sendable {
  public var provider: LLMProvider
  public var model: String
  public var baseURL: URL?
  public var apiKey: String?

  public init(
    provider: LLMProvider,
    model: String,
    baseURL: URL?,
    apiKey: String?
  ) {
    self.provider = provider
    self.model = model
    self.baseURL = baseURL
    self.apiKey = apiKey
  }
}

/// HTTP-backed notes summarization (Ollama, OpenAI Responses, OpenAI-compatible chat, Anthropic Messages).
public actor HTTPNotesSummarizer: NotesSummarizing {
  private let config: HTTPNotesSummarizerConfig
  private let diagnostics: any DiagnosticsLogging
  private let llmClient: LLMHTTPClient

  public init(
    config: HTTPNotesSummarizerConfig,
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger(),
    urlSession: URLSession = .shared
  ) {
    self.config = config
    self.diagnostics = diagnostics
    self.llmClient = LLMHTTPClient(
      urlSession: urlSession,
      diagnostics: diagnostics,
      category: "notes"
    )
  }

  public func summarize(_ request: NotesSummarizationRequest) async throws -> NotesSummary {
    switch config.provider {
    case .ollama:
      return try await summarizeWithOllama(request)
    case .openAI:
      return try await summarizeWithOpenAIResponses(request)
    case .openAICompatible:
      return try await summarizeWithOpenAIChatCompletions(request)
    case .anthropic:
      return try await summarizeWithAnthropic(request)
    case .off, .externalExecutable:
      throw NSError(
        domain: "NoteStream", code: 90,
        userInfo: [
          NSLocalizedDescriptionKey:
            "HTTP summarizer does not support provider \(config.provider.rawValue)."
        ])
    }
  }

  // MARK: - Ollama

  private func summarizeWithOllama(_ request: NotesSummarizationRequest) async throws
    -> NotesSummary
  {
    let url = try LLMEndpointBuilder.ollamaChat(baseURL: config.baseURL)

    let body: [String: Any] = [
      "model": config.model,
      "stream": false,
      "format": NotesJSONSchema.notesSummary,
      "messages": [
        [
          "role": "system",
          "content":
            "You convert transcripts into structured notes. Return JSON matching the provided schema.",
        ],
        [
          "role": "user",
          "content": NotesPromptBuilder.buildPrompt(request),
        ],
      ],
    ]

    let data = try await llmClient.postJSON(url: url, headers: [:], body: body)
    let content = try LLMResponseExtractor.ollamaMessageContent(from: data)

    let summary = try NotesResponseDecoder.decode(content)
    await diagnostics.log(
      .init(
        level: .info, category: "notes", message: "ollama_notes_ok",
        metadata: ["title": summary.title]))
    return summary
  }

  // MARK: - OpenAI (Responses API)

  private func summarizeWithOpenAIResponses(_ request: NotesSummarizationRequest) async throws
    -> NotesSummary
  {
    guard let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw NSError(
        domain: "NoteStream", code: 94,
        userInfo: [
          NSLocalizedDescriptionKey: "API key is missing."
        ])
    }

    let url = try LLMEndpointBuilder.openAIResponses()

    let body: [String: Any] = [
      "model": config.model,
      "input": [
        [
          "role": "system",
          "content":
            "You convert transcripts into structured notes. Return only schema-valid JSON.",
        ],
        [
          "role": "user",
          "content": NotesPromptBuilder.buildPrompt(request),
        ],
      ],
      "text": [
        "format": [
          "type": "json_schema",
          "name": "notestream_notes_summary",
          "strict": true,
          "schema": NotesJSONSchema.notesSummary,
        ]
      ],
    ]

    let data = try await llmClient.postJSON(
      url: url,
      headers: [
        "Authorization": "Bearer \(apiKey)"
      ],
      body: body
    )

    let text = try LLMResponseExtractor.openAINotesText(from: data)
    let summary = try NotesResponseDecoder.decode(text)
    await diagnostics.log(
      .init(
        level: .info, category: "notes", message: "openai_notes_ok",
        metadata: ["title": summary.title]))
    return summary
  }

  // MARK: - OpenAI-compatible (Chat Completions + JSON)

  private func summarizeWithOpenAIChatCompletions(_ request: NotesSummarizationRequest) async throws
    -> NotesSummary
  {
    let url = try LLMEndpointBuilder.openAICompatibleChat(
      provider: .openAICompatible,
      baseURL: config.baseURL
    )

    var headers: [String: String] = [:]
    if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
      headers["Authorization"] = "Bearer \(key)"
    }

    let body: [String: Any] = [
      "model": config.model,
      "messages": [
        [
          "role": "system",
          "content": """
          You convert transcripts into structured notes. Respond with a single JSON object only, matching this shape:
          {"title":"string","summaryMarkdown":"string","keyPoints":[],"actionItems":[],"openQuestions":[],"topicTimeline":[]}
          topicTimeline is optional: 5 to 12 items with startTime (seconds), title, optional summary.
          """,
        ],
        [
          "role": "user",
          "content": NotesPromptBuilder.buildPrompt(request),
        ],
      ],
      "response_format": [
        "type": "json_object"
      ],
    ]

    let data = try await llmClient.postJSON(url: url, headers: headers, body: body)

    let text = try LLMResponseExtractor.openAIChatContent(from: data)

    let summary = try NotesResponseDecoder.decode(text)
    await diagnostics.log(
      .init(
        level: .info, category: "notes", message: "openai_compatible_notes_ok",
        metadata: ["title": summary.title]))
    return summary
  }

  // MARK: - Anthropic

  private func summarizeWithAnthropic(_ request: NotesSummarizationRequest) async throws
    -> NotesSummary
  {
    guard let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw NSError(
        domain: "NoteStream", code: 96,
        userInfo: [
          NSLocalizedDescriptionKey: "Anthropic API key is missing."
        ])
    }

    let url = try LLMEndpointBuilder.anthropicMessages()

    let body: [String: Any] = [
      "model": config.model,
      "max_tokens": 2000,
      "system": """
      You convert transcripts into structured notes.
      Return JSON only with this exact shape:
      {
        "title": "string",
        "summaryMarkdown": "string",
        "keyPoints": ["string"],
        "actionItems": ["string"],
        "openQuestions": ["string"],
        "topicTimeline": [{"id":"string-uuid","startTime":0,"title":"string","summary":"string or null"}]
      }
      topicTimeline is optional; omit the key or use an empty array if not applicable.
      """,
      "messages": [
        [
          "role": "user",
          "content": NotesPromptBuilder.buildPrompt(request),
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

    let summary = try NotesResponseDecoder.decode(text)
    await diagnostics.log(
      .init(
        level: .info, category: "notes", message: "anthropic_notes_ok",
        metadata: ["title": summary.title]))
    return summary
  }
}
