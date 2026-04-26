import Foundation
import Testing

@testable import NoteStreamCore

@Test func generatedTitleFormatterTrimsAndRemovesIllegalCharacters() {
  let title = GeneratedTitleFormatter.sanitize("  Austin / Housing: Debate?  ")
  #expect(title == "Austin Housing Debate")
}

@Test func generatedTitleFormatterRejectsGenericTitles() {
  #expect(GeneratedTitleFormatter.sanitize("Summary") == nil)
  #expect(GeneratedTitleFormatter.sanitize("Recording") == nil)
}

@Test func generatedTitleFormatterLimitsLength() {
  let raw = String(repeating: "Housing ", count: 20)
  let title = GeneratedTitleFormatter.sanitize(raw, maxLength: 20)
  #expect(title?.hasSuffix("…") == true)
  #expect((title?.count ?? 0) <= 21)
}
