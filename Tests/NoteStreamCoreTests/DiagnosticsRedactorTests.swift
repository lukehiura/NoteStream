import Foundation
import XCTest

@testable import NoteStreamCore

final class DiagnosticsRedactorTests: XCTestCase {
  func testDiagnosticsRedactorSanitizeTruncatesLongMessages() {
    let long = String(repeating: "a", count: 600)
    let event = DiagnosticsEvent(level: .info, category: "test", message: long, metadata: [:])
    let out = DiagnosticsRedactor.sanitize(event)
    XCTAssertLessThan(out.message.count, long.count)
  }

  func testDiagnosticsRedactorSanitizeMetadataKeys() {
    let event = DiagnosticsEvent(
      level: .debug,
      category: "llm",
      message: "ok",
      metadata: ["apiKey": "sk-secret", "safe": "yes"]
    )
    let out = DiagnosticsRedactor.sanitize(event)
    XCTAssertEqual(out.metadata["apiKey"], "<redacted>")
    XCTAssertEqual(out.metadata["safe"], "yes")
  }
}
