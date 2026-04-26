import SwiftUI

struct GeneralSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  @State private var showingResetIntegrationsConfirm = false
  @State private var showingResetSpeakersConfirm = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          Text("Maintenance actions")
            .font(.headline)

          Text(
            "These reset local app settings only. They do not delete recordings, transcripts, or notes."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          HStack(spacing: 10) {
            Button {
              showingResetIntegrationsConfirm = true
            } label: {
              Label("Reset Tool Integrations", systemImage: "wrench.and.screwdriver")
            }

            Button {
              showingResetSpeakersConfirm = true
            } label: {
              Label("Reset Speaker Settings", systemImage: "person.2.slash")
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            Text(
              "Reset Tool Integrations clears custom executable paths for advanced diarizer and summarizer tools."
            )
            Text("Reset Speaker Settings restores speaker-label preferences to defaults.")
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
      } label: {
        Label("General", systemImage: "gearshape")
      }

      SupportSettingsView()
    }
    .alert("Reset tool integrations?", isPresented: $showingResetIntegrationsConfirm) {
      Button("Reset", role: .destructive) {
        model.resetExternalToolIntegrations()
      }

      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This clears custom executable paths for advanced external tools. It does not delete transcripts, audio, notes, API keys, or recordings."
      )
    }
    .alert("Reset speaker settings?", isPresented: $showingResetSpeakersConfirm) {
      Button("Reset", role: .destructive) {
        model.resetSpeakerPreferencesForDebug()
      }

      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This restores speaker-label settings to defaults. It does not modify saved transcripts.")
    }
  }
}
