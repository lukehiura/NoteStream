import NoteStreamInfrastructure
import SwiftUI

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
