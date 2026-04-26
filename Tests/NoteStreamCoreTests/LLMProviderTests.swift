import Foundation
import Testing

@testable import NoteStreamCore

@Test func llmProviderRoundTripRawValue() {
  for provider in LLMProvider.allCases {
    #expect(LLMProvider(rawValue: provider.rawValue) == provider)
  }
}

@Test func llmProviderTitlesAreNonEmpty() {
  for provider in LLMProvider.allCases {
    #expect(!provider.title.isEmpty)
  }
}

@Test func localLLMPresetRoundTripRawValue() {
  for preset in LocalLLMPreset.allCases {
    #expect(LocalLLMPreset(rawValue: preset.rawValue) == preset)
  }
}
