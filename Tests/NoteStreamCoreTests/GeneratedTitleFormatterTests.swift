import Foundation
import XCTest

@testable import NoteStreamCore

final class GeneratedTitleFormatterTests: XCTestCase {
  func testGeneratedTitleFormatterTrimsAndRemovesIllegalCharacters() {
    let title = GeneratedTitleFormatter.sanitize("  Austin / Housing: Debate?  ")
    XCTAssertEqual(title, "Austin Housing Debate")
  }

  func testGeneratedTitleFormatterRejectsGenericTitles() {
    XCTAssertNil(GeneratedTitleFormatter.sanitize("Summary"))
    XCTAssertNil(GeneratedTitleFormatter.sanitize("Recording"))
  }

  func testGeneratedTitleFormatterLimitsLength() {
    let raw = String(repeating: "Housing ", count: 20)
    let title = GeneratedTitleFormatter.sanitize(raw, maxLength: 20)
    XCTAssertTrue(title?.hasSuffix("…") == true)
    XCTAssertLessThanOrEqual(title?.count ?? 0, 21)
  }
}
