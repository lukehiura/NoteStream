import Foundation
import Testing

@testable import NoteStreamCore

@Test func diagnosticsRedactorSanitizeTruncatesLongMessages() {
  let long = String(repeating: "a", count: 600)
  let event = DiagnosticsEvent(level: .info, category: "test", message: long, metadata: [:])
  let out = DiagnosticsRedactor.sanitize(event)
  #expect(out.message.count < long.count)
}

@Test func diagnosticsRedactorSanitizeMetadataKeys() {
  let event = DiagnosticsEvent(
    level: .debug,
    category: "llm",
    message: "ok",
    metadata: ["apiKey": "sk-secret", "safe": "yes"]
  )
  let out = DiagnosticsRedactor.sanitize(event)
  #expect(out.metadata["apiKey"] == "<redacted>")
  #expect(out.metadata["safe"] == "yes")
}
