import Foundation
import NoteStreamCore
import XCTest

@testable import NoteStreamInfrastructure

/// URLProtocol stub for `HTTPNotesSummarizer` tests. Handlers are keyed by `baseURL` (scheme + host + port)
/// so concurrent tests do not overwrite each other’s responses.
private final class MockURLProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

  private static func registryKey(for url: URL) -> String {
    guard let host = url.host else { return url.absoluteString }
    let portPart = url.port.map { ":\($0)" } ?? ""
    return "\(url.scheme ?? "http")://\(host)\(portPart)"
  }

  static func setHandler(
    for baseURL: URL,
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) {
    lock.lock()
    defer { lock.unlock() }
    handlers[registryKey(for: baseURL)] = handler
  }

  static func removeHandler(for baseURL: URL) {
    lock.lock()
    defer { lock.unlock() }
    handlers.removeValue(forKey: registryKey(for: baseURL))
  }

  override static func canInit(with request: URLRequest) -> Bool { true }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(
        self,
        didFailWithError: NSError(
          domain: "MockURLProtocol", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Missing URL"]
        )
      )
      return
    }

    Self.lock.lock()
    let handler = Self.handlers[Self.registryKey(for: url)]
    Self.lock.unlock()

    guard let handler = handler else {
      client?.urlProtocol(
        self,
        didFailWithError: NSError(
          domain: "MockURLProtocol", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: "No handler registered for \(Self.registryKey(for: url))"
          ]
        )
      )
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [MockURLProtocol.self]
  return URLSession(configuration: config)
}

/// Unique mock origin per test (no real network; `URLProtocol` intercepts). Uses host, not random ports.
private func mockBaseURL(testID: String) -> URL {
  guard let url = URL(string: "https://\(testID).mock.notestream.test") else {
    preconditionFailure("invalid mock URL")
  }
  return url
}

private func httpBodyData(from request: URLRequest) -> Data? {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return nil }
  stream.open()
  defer { stream.close() }
  var data = Data()
  let bufferSize = 4096
  let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
  defer { buffer.deallocate() }
  while stream.hasBytesAvailable {
    let read = stream.read(buffer, maxLength: bufferSize)
    if read < 0 { return nil }
    if read == 0 { break }
    data.append(buffer, count: read)
  }
  return data
}

final class HTTPNotesSummarizerTests: XCTestCase {
  func testOllamaParsesMessageContentJSON() async throws {
    let notes = NotesSummary(
      title: "T",
      summaryMarkdown: "## Summary\nx",
      keyPoints: ["k"],
      actionItems: [],
      openQuestions: []
    )
    let inner = try XCTUnwrap(String(data: try JSONEncoder().encode(notes), encoding: .utf8))
    let envelope: [String: Any] = [
      "message": [
        "content": inner
      ]
    ]
    let body = try JSONSerialization.data(withJSONObject: envelope)

    let base = mockBaseURL(testID: "ollama-parse")
    MockURLProtocol.setHandler(for: base) { request in
      XCTAssertTrue(request.url?.absoluteString.contains("/api/chat") == true)
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )
      )
      return (response, body)
    }
    defer { MockURLProtocol.removeHandler(for: base) }

    let config = HTTPNotesSummarizerConfig(
      provider: .ollama, model: "m", baseURL: base, apiKey: nil)
    let summarizer = HTTPNotesSummarizer(config: config, urlSession: makeMockSession())

    let out = try await summarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: "hello",
        previousNotesMarkdown: nil,
        mode: .final
      )
    )

    XCTAssertEqual(out.title, notes.title)
    XCTAssertEqual(out.summaryMarkdown, notes.summaryMarkdown)
    XCTAssertEqual(out.keyPoints, notes.keyPoints)
  }

  func testOpenAICompatibleParsesChatCompletionContent() async throws {
    let notes = NotesSummary(
      title: "Chat",
      summaryMarkdown: "## Summary\ny",
      keyPoints: [],
      actionItems: [],
      openQuestions: []
    )
    let content = try XCTUnwrap(String(data: try JSONEncoder().encode(notes), encoding: .utf8))
    let root: [String: Any] = [
      "choices": [
        [
          "message": [
            "role": "assistant",
            "content": content,
          ]
        ]
      ]
    ]
    let body = try JSONSerialization.data(withJSONObject: root)

    let base = mockBaseURL(testID: "openai-compat")
    MockURLProtocol.setHandler(for: base) { request in
      XCTAssertTrue(request.url?.path.contains("chat/completions") == true)
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
      )
      return (response, body)
    }
    defer { MockURLProtocol.removeHandler(for: base) }

    let config = HTTPNotesSummarizerConfig(
      provider: .openAICompatible,
      model: "local",
      baseURL: base,
      apiKey: nil
    )
    let summarizer = HTTPNotesSummarizer(config: config, urlSession: makeMockSession())

    let out = try await summarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: "x",
        previousNotesMarkdown: nil,
        mode: .final
      )
    )

    XCTAssertEqual(out.title, "Chat")
  }

  func testPropagatesNon2xxHTTPAsError() async throws {
    let base = mockBaseURL(testID: "http-503")
    MockURLProtocol.setHandler(for: base) { request in
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
      )
      return (response, Data("upstream".utf8))
    }
    defer { MockURLProtocol.removeHandler(for: base) }

    let config = HTTPNotesSummarizerConfig(
      provider: .ollama, model: "m", baseURL: base, apiKey: nil)
    let summarizer = HTTPNotesSummarizer(config: config, urlSession: makeMockSession())

    do {
      _ = try await summarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: "x",
          previousNotesMarkdown: nil,
          mode: .final
        )
      )
      XCTFail("Expected summarize to throw")
    } catch {
      XCTAssertNotNil(error)
    }
  }

  func testOllamaPromptIncludesNotesPreferences() async throws {
    let notes = NotesSummary(
      title: "T",
      summaryMarkdown: "## Summary\nx",
      keyPoints: [],
      actionItems: [],
      openQuestions: [],
      topicTimeline: []
    )

    let inner = try XCTUnwrap(String(data: try JSONEncoder().encode(notes), encoding: .utf8))
    let envelope: [String: Any] = [
      "message": [
        "content": inner
      ]
    ]
    let responseBody = try JSONSerialization.data(withJSONObject: envelope)

    let base = mockBaseURL(testID: "ollama-prefs")
    MockURLProtocol.setHandler(for: base) { request in
      let requestData = try XCTUnwrap(httpBodyData(from: request))
      let body = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
      let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
      let user = try XCTUnwrap(messages.last?["content"] as? String)

      XCTAssertTrue(user.contains("Create detailed notes") || user.contains("detailed notes"))
      XCTAssertTrue(user.contains("executive brief"))
      XCTAssertTrue(user.contains("Focus on decisions"))

      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
      )

      return (response, responseBody)
    }
    defer { MockURLProtocol.removeHandler(for: base) }

    let summarizer = HTTPNotesSummarizer(
      config: HTTPNotesSummarizerConfig(
        provider: .ollama,
        model: "m",
        baseURL: base,
        apiKey: nil
      ),
      urlSession: makeMockSession()
    )

    _ = try await summarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: "hello",
        previousNotesMarkdown: nil,
        mode: .final,
        preferences: NotesGenerationPreferences(
          detailLevel: .detailed,
          tone: .executive,
          language: .sameAsTranscript,
          sections: .standard,
          customInstructions: "Focus on decisions",
          liveUpdateStyle: .brief
        )
      )
    )
  }
}
