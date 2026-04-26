import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
          SettingsRow(label: "Model") {
            ModelPickerControl(model: model)
          }
        }

        Toggle("Delete audio after transcription", isOn: $model.deleteAudioAfterTranscription)
          .toggleStyle(.switch)

        Text("Keeping audio allows playback, re-transcription, and speaker reprocessing.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Transcription", systemImage: "waveform")
    }
  }
}
