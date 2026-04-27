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

  // MARK: - Schema & prompt

  private var notesSchema: [String: Any] {
    let topicTimelineItemSchema: [String: Any] = [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "id": ["type": "string"],
        "startTime": ["type": "number"],
        "title": ["type": "string"],
        "summary": [
          "anyOf": [
            ["type": "string"],
            ["type": "null"],
          ]
        ],
      ],
      "required": ["id", "startTime", "title", "summary"],
    ]

    return [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "title": ["type": "string"],
        "summaryMarkdown": ["type": "string"],
        "keyPoints": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "actionItems": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "openQuestions": [
          "type": "array",
          "items": ["type": "string"],
        ],
        "topicTimeline": [
          "type": "array",
          "items": topicTimelineItemSchema,
        ],
      ],
      "required": [
        "title",
        "summaryMarkdown",
        "keyPoints",
        "actionItems",
        "openQuestions",
        "topicTimeline",
      ],
    ]
  }

  private func sectionInstruction(_ sections: NotesSectionPreferences) -> String {
    var enabled: [String] = []

    if sections.summary { enabled.append("Summary") }
    if sections.keyPoints { enabled.append("Key Points") }
    if sections.actionItems { enabled.append("Action Items") }
    if sections.openQuestions { enabled.append("Open Questions") }
    if sections.decisions { enabled.append("Decisions") }
    if sections.topicTimeline { enabled.append("Topic Timeline") }
    if sections.speakerHighlights { enabled.append("Speaker Highlights") }

    if enabled.isEmpty {
      return "Include a short Summary section."
    }

    return "Include these sections in summaryMarkdown: \(enabled.joined(separator: ", "))."
  }

  private func topicTimelineInstruction(_ sections: NotesSectionPreferences) -> String {
    guard sections.topicTimeline else {
      return "Set topicTimeline to an empty array if the schema requires it."
    }

    return """
      Create topicTimeline with 5 to 12 timestamped items when enough transcript exists.
      Each topicTimeline item should include startTime in seconds, title, and optional summary.
      """
  }

  private func customInstructionBlock(_ text: String) -> String {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return "No custom user instructions." }

    return """
      User custom instructions:
      \(cleaned)
      """
  }

  private func buildPrompt(_ request: NotesSummarizationRequest) -> String {
    let prefs = request.preferences
    let sections = sectionInstruction(prefs.sections)
    let custom = customInstructionBlock(prefs.customInstructions)

    switch request.mode {
    case .final:
      return """
        Create structured notes from this transcript.

        Rules:
        - Return JSON only.
        - Do not invent facts.
        - Keep speaker labels when useful.
        - Create a short, specific title.
        - Title must be 4 to 9 words.
        - Do not include dates, file names, or generic words like "Recording" or "Transcript".
        - \(prefs.detailLevel.promptInstruction)
        - \(prefs.tone.promptInstruction)
        - \(prefs.language.promptInstruction)
        - \(sections)
        - \(topicTimelineInstruction(prefs.sections))
        - Use empty arrays when there are no action items or open questions.
        - Preserve uncertainty when the transcript is unclear.

        \(custom)

        Transcript:
        \(request.transcriptMarkdown)
        """

    case .liveUpdate:
      return """
        Update running notes from a live transcript.

        Rules:
        - Return JSON only.
        - Merge the new transcript into previous notes.
        - Do not duplicate previous points.
        - Do not invent facts.
        - Keep the notes stable. Do not rewrite everything unless needed.
        - \(prefs.liveUpdateStyle.promptInstruction)
        - \(prefs.tone.promptInstruction)
        - \(prefs.language.promptInstruction)
        - \(sections)
        - Keep live notes provisional. Prefer concise updates.
        - Preserve existing useful notes from previousNotesMarkdown.

        \(custom)

        Previous notes:
        \(request.previousNotesMarkdown ?? "(none)")

        New transcript:
        \(request.transcriptMarkdown)
        """
    }
  }

  private func decodeNotesFromJSONText(_ text: String) throws -> NotesSummary {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("```") {
      s.removeFirst(3)
      if let newline = s.firstIndex(of: "\n") {
        s = String(s[s.index(after: newline)...])
      }
      s = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if s.hasSuffix("```") {
        s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    guard let data = s.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 91,
        userInfo: [
          NSLocalizedDescriptionKey: "LLM response was not UTF-8."
        ])
    }

    return try JSONDecoder().decode(NotesSummary.self, from: data)
  }

  // MARK: - Ollama

  private func summarizeWithOllama(_ request: NotesSummarizationRequest) async throws
    -> NotesSummary
  {
    let url = try LLMEndpointBuilder.ollamaChat(baseURL: config.baseURL)

    let body: [String: Any] = [
      "model": config.model,
      "stream": false,
      "format": notesSchema,
      "messages": [
        [
          "role": "system",
          "content":
            "You convert transcripts into structured notes. Return JSON matching the provided schema.",
        ],
        [
          "role": "user",
          "content": buildPrompt(request),
        ],
      ],
    ]

    let data = try await llmClient.postJSON(url: url, headers: [:], body: body)
    let content = try LLMResponseExtractor.ollamaMessageContent(from: data)

    let summary = try decodeNotesFromJSONText(content)
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
          "content": buildPrompt(request),
        ],
      ],
      "text": [
        "format": [
          "type": "json_schema",
          "name": "notestream_notes_summary",
          "strict": true,
          "schema": notesSchema,
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
    let summary = try decodeNotesFromJSONText(text)
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
          "content": buildPrompt(request),
        ],
      ],
      "response_format": [
        "type": "json_object"
      ],
    ]

    let data = try await llmClient.postJSON(url: url, headers: headers, body: body)

    let text = try LLMResponseExtractor.openAIChatContent(from: data)

    let summary = try decodeNotesFromJSONText(text)
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
          "content": buildPrompt(request),
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

    let summary = try decodeNotesFromJSONText(text)
    await diagnostics.log(
      .init(
        level: .info, category: "notes", message: "anthropic_notes_ok",
        metadata: ["title": summary.title]))
    return summary
  }
}
