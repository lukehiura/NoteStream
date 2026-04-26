import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct RecoveryPanel: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recover recordings")
        .font(.title3.weight(.semibold))

      Text("These recordings have audio files but no completed session.")
        .foregroundStyle(.secondary)

      List(model.recoverableAudioFiles, id: \.path) { url in
        HStack {
          VStack(alignment: .leading) {
            Text(url.lastPathComponent)
            Text(url.deletingLastPathComponent().lastPathComponent)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Transcribe") {
            model.recoverRecording(at: url)
            model.showingRecoveryPanel = false
          }
        }
      }

      HStack {
        Spacer()
        Button("Close") {
          model.showingRecoveryPanel = false
        }
      }
    }
    .padding()
  }
}

struct PermissionPanel: View {
  var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Screen Recording permission required")
        .font(.title3.weight(.semibold))

      Text(
        "To capture system audio, enable NoteStream in System Settings → Privacy & Security → Screen Recording. You may need to restart the app after granting permission."
      )
      .foregroundStyle(.secondary)

      HStack {
        Button("Open System Settings") {
          ScreenRecordingPermission.openSystemSettings()
        }
        Button("Check Again") {
          Task {
            _ = await ScreenRecordingPermission.request()
            await MainActor.run {
              if ScreenRecordingPermission.hasPermission() {
                model.showingPermissionPanel = false
              }
            }
          }
        }
        Spacer()
        Button("Close") { model.showingPermissionPanel = false }
      }
    }
    .padding(16)
  }
}

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
