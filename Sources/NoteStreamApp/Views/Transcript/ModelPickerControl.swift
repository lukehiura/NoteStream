import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct ModelPickerControl: View {
  @Bindable var model: TranscriptionViewModel
  var compact: Bool = false

  var body: some View {
    Picker(compact ? "Model" : "Transcription model", selection: $model.selectedModel) {
      Text(SpeechModelDisplay.name(for: "base.en")).tag("base.en")
      Text(SpeechModelDisplay.name(for: "small.en")).tag("small.en")
      Text(SpeechModelDisplay.name(for: "medium.en")).tag("medium.en")
    }
    .labelsHidden()
    .frame(width: compact ? 120 : nil)
    .onChange(of: model.selectedModel) { _, _ in
      model.prepareSelectedModelIfNeeded(force: true)
    }
    .help("Choose the local Whisper transcription model.")
  }
}
