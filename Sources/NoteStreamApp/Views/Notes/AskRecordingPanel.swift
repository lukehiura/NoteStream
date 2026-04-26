import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct AskRecordingPanel: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()

      HStack {
        Text("Ask this Recording")
          .font(.headline)

        Spacer()

        if model.isAnsweringQuestion {
          ProgressView()
            .controlSize(.small)
        }
      }

      TextField("Ask about this transcript…", text: $model.askQuestionText)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          model.askCurrentRecording()
        }

      HStack {
        Button("Ask") {
          model.askCurrentRecording()
        }
        .disabled(!model.canAskRecording)

        if let status = model.askStatusText {
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if !model.askAnswerMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ScrollView {
          Text(.init(model.askAnswerMarkdown))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120, maxHeight: 240)
      }
    }
  }
}
