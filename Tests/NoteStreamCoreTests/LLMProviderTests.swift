import Foundation
import XCTest

@testable import NoteStreamCore

final class LLMProviderTests: XCTestCase {
  func testLlmProviderRoundTripRawValue() {
    for provider in LLMProvider.allCases {
      XCTAssertEqual(LLMProvider(rawValue: provider.rawValue), provider)
    }
  }

  func testLlmProviderTitlesAreNonEmpty() {
    for provider in LLMProvider.allCases {
      XCTAssertFalse(provider.title.isEmpty)
    }
  }

  func testLocalLLMPresetRoundTripRawValue() {
    for preset in LocalLLMPreset.allCases {
      XCTAssertEqual(LocalLLMPreset(rawValue: preset.rawValue), preset)
    }
  }
}
