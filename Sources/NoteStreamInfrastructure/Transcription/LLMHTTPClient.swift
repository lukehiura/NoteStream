import Foundation
import NoteStreamCore

struct LLMHTTPClient: Sendable {
  private let urlSession: URLSession
  private let diagnostics: any DiagnosticsLogging
  private let category: String

  init(
    urlSession: URLSession = .shared,
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger(),
    category: String = "llm"
  ) {
    self.urlSession = urlSession
    self.diagnostics = diagnostics
    self.category = category
  }

  func postJSON(
    url: URL,
    headers: [String: String],
    body: [String: Any],
    timeoutSeconds: TimeInterval = 90
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeoutSeconds
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    await diagnostics.log(
      .init(
        level: .info,
        category: category,
        message: "llm_http_request",
        metadata: [
          "url": url.absoluteString
        ]
      ))

    let (data, response) = try await urlSession.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      return data
    }

    guard (200..<300).contains(http.statusCode) else {
      let text = String(data: data, encoding: .utf8) ?? ""
      throw NoteStreamError.httpFailure(status: http.statusCode, body: text)
    }

    return data
  }
}
