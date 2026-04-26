import Foundation
import NoteStreamCore

/// LLM-backed Q&A over a transcript (Ollama chat, OpenAI chat completions, Anthropic Messages).
public final class HTTPRecordingQuestionAnswerer: RecordingQuestionAnswering, @unchecked Sendable {
  private let config: HTTPNotesSummarizerConfig
  private let urlSession: URLSession

  public init(
    config: HTTPNotesSummarizerConfig,
    urlSession: URLSession = .shared
  ) {
    self.config = config
    self.urlSession = urlSession
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
    let base =
      config.baseURL ?? (URL(string: "http://localhost:11434") ?? URL(fileURLWithPath: "/"))
    let url = base.appendingPathComponent("api").appendingPathComponent("chat")

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

    let data = try await runJSONRequest(url: url, headers: [:], body: body)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message = root?["message"] as? [String: Any]
    let content = message?["content"] as? String ?? ""

    return RecordingQuestionAnswer(answerMarkdown: content)
  }

  private func answerWithOpenAICompatible(_ request: RecordingQuestionRequest) async throws
    -> RecordingQuestionAnswer
  {
    let base: URL
    if config.provider == .openAI {
      base = URL(string: "https://api.openai.com/v1") ?? URL(fileURLWithPath: "/")
    } else if let baseURL = config.baseURL {
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

    var headers: [String: String] = [:]
    if let apiKey = config.apiKey, !apiKey.isEmpty {
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

    let data = try await runJSONRequest(url: url, headers: headers, body: body)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let choices = root?["choices"] as? [[String: Any]]
    let message = choices?.first?["message"] as? [String: Any]
    let content = message?["content"] as? String ?? ""

    return RecordingQuestionAnswer(answerMarkdown: content)
  }

  private func answerWithAnthropic(_ request: RecordingQuestionRequest) async throws
    -> RecordingQuestionAnswer
  {
    guard let apiKey = config.apiKey, !apiKey.isEmpty else {
      throw NoteStreamError.missingAnthropicAPIKey
    }

    let url = URL(string: "https://api.anthropic.com/v1/messages") ?? URL(fileURLWithPath: "/")

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

    let data = try await runJSONRequest(
      url: url,
      headers: [
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      ],
      body: body
    )

    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let contentBlocks = root?["content"] as? [[String: Any]]
    let text =
      contentBlocks?
      .compactMap { $0["text"] as? String }
      .joined(separator: "\n") ?? ""

    return RecordingQuestionAnswer(answerMarkdown: text)
  }

  private func runJSONRequest(
    url: URL,
    headers: [String: String],
    body: [String: Any]
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await urlSession.data(for: request)

    if let http = response as? HTTPURLResponse,
      !(200..<300).contains(http.statusCode)
    {
      let text = String(data: data, encoding: .utf8) ?? ""
      throw NoteStreamError.httpFailure(status: http.statusCode, body: text)
    }

    return data
  }
}
