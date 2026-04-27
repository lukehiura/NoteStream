import SwiftUI

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
