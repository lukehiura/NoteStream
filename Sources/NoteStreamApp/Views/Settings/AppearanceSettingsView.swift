import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        Text("Choose how NoteStream should appear.")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Theme", selection: $model.appearanceMode) {
          ForEach(AppAppearanceMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)

        Text("System follows your macOS appearance setting.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Theme", systemImage: "circle.lefthalf.filled")
    }
  }
}
