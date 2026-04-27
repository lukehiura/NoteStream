import NoteStreamCore
import SwiftUI

struct ModelPanel: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text("Model Status")
          .font(.title3.weight(.semibold))

        HStack(spacing: 12) {
          Text("Selected model:")
            .foregroundStyle(.secondary)

          Text(model.selectedModel)
            .font(.callout.monospaced())

          Spacer()
        }

        if let status = model.modelStatus, status.model == model.selectedModel {
          statusView(status)
        } else {
          Text("No status yet.")
            .foregroundStyle(.secondary)
        }

        Divider()

        HStack {
          Button("Prepare") {
            model.prepareModel()
          }

          Button("Retry") {
            model.retryModel()
          }

          Button("Clear cached models") {
            model.clearModelCache()
          }

          Spacer()

          Button("Close") {
            model.showingModelPanel = false
          }
        }
      }
      .padding(16)
    }
  }

  @ViewBuilder
  private func statusView(_ status: ModelStatus) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(String(describing: status.state))
        .font(.headline)

      if let detail = status.detail, !detail.isEmpty {
        Text(detail)
          .foregroundStyle(.secondary)
      }
    }
  }
}
