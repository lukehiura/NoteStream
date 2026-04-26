import Foundation
import NoteStreamCore
import XCTest

@testable import NoteStreamInfrastructure

/// URLProtocol stub for `HTTPNotesSummarizer` tests (must not run in parallel with itself).
private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override static func canInit(with request: URLRequest) -> Bool { true }

  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(
        self,
        didFailWithError: NSError(
          domain: "MockURLProtocol", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: "Handler not set"
          ])
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

    MockURLProtocol.handler = { request in
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
    defer { MockURLProtocol.handler = nil }

    let base = try XCTUnwrap(URL(string: "http://127.0.0.1:9"))
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

    MockURLProtocol.handler = { request in
      XCTAssertTrue(request.url?.path.contains("chat/completions") == true)
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
      )
      return (response, body)
    }
    defer { MockURLProtocol.handler = nil }

    let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8"))
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
    MockURLProtocol.handler = { request in
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
      )
      return (response, Data("upstream".utf8))
    }
    defer { MockURLProtocol.handler = nil }

    let base = try XCTUnwrap(URL(string: "http://127.0.0.1:7"))
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

    MockURLProtocol.handler = { request in
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
    defer { MockURLProtocol.handler = nil }

    let base = try XCTUnwrap(URL(string: "http://127.0.0.1:9"))
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
