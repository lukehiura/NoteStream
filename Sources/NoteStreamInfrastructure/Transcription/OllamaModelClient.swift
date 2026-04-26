import Foundation
import NoteStreamCore

public actor OllamaModelClient {
  private let baseURL: URL
  private let diagnostics: any DiagnosticsLogging
  private let urlSession: URLSession

  public init(
    baseURL: URL = URL(string: "http://localhost:11434") ?? URL(fileURLWithPath: "/"),
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger(),
    urlSession: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.diagnostics = diagnostics
    self.urlSession = urlSession
  }

  public func listLocalModels() async throws -> [LocalLLMModel] {
    let url = baseURL.appendingPathComponent("api").appendingPathComponent("tags")

    let (data, response) = try await urlSession.data(from: url)

    if let http = response as? HTTPURLResponse,
      !(200..<300).contains(http.statusCode)
    {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "NoteStream", code: http.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Ollama model list failed with HTTP \(http.statusCode): \(body)"
        ])
    }

    let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

    return decoded.models
      .map { model in
        LocalLLMModel(
          name: model.name,
          displayName: model.name,
          sizeBytes: model.size
        )
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func pullModel(_ modelName: String) async throws {
    let url = baseURL.appendingPathComponent("api").appendingPathComponent("pull")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 600
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "model": modelName,
      "stream": false,
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await urlSession.data(for: request)

    if let http = response as? HTTPURLResponse,
      !(200..<300).contains(http.statusCode)
    {
      let text = String(data: data, encoding: .utf8) ?? ""
      throw NSError(
        domain: "NoteStream", code: http.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Ollama pull failed with HTTP \(http.statusCode): \(text)"
        ])
    }

    await diagnostics.log(
      .init(
        level: .info,
        category: "llm",
        message: "ollama_model_pulled",
        metadata: ["model": modelName]
      ))
  }
}

private struct OllamaTagsResponse: Decodable {
  var models: [OllamaModel]
}

private struct OllamaModel: Decodable {
  var name: String
  var model: String?
  var size: Int64?

  enum CodingKeys: String, CodingKey {
    case name
    case model
    case size
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
    let decodedModel = try container.decodeIfPresent(String.self, forKey: .model)

    self.name = decodedName ?? decodedModel ?? "unknown"
    self.model = decodedModel
    self.size = try container.decodeIfPresent(Int64.self, forKey: .size)
  }
}
