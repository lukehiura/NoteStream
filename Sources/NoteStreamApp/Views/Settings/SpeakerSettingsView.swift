import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SpeakerWorkflowStatusCard: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Speaker Workflow", systemImage: "person.2.wave.2")
          .font(.headline)

        Spacer()

        SpeakerModePill(model: model)
      }

      Text(
        model.liveSpeakerDiarizationEnabled && model.realSpeakerDiarizationIsReady
          ? "Live preview can show provisional speaker labels during recording. Final labels still run on the full file after Stop & Transcribe."
          : "Speaker labels are applied after Stop & Transcribe unless Live Preview is enabled and a real diarizer is configured."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        Label(
          model.speakerDiarizationEnabled
            ? "Speaker labeling is enabled" : "Speaker labeling is off",
          systemImage: model.speakerDiarizationEnabled ? "checkmark.circle.fill" : "pause.circle"
        )

        Label(
          model.realSpeakerDiarizationIsReady
            ? "Real diarizer configured" : "No real diarizer configured",
          systemImage: model.realSpeakerDiarizationIsReady
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )

        #if DEBUG
          if model.speakerDiarizerModeText.contains("Debug") {
            Label("Debug mode uses fake speaker turns", systemImage: "ladybug.fill")
              .foregroundStyle(.orange)
          }
        #endif
      }
      .font(.caption)

      Text(model.speakerSetupStatusText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let live = model.liveSpeakerStatusText, !live.isEmpty {
        Text(live)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(AppSurface.subtleFill)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(AppSurface.separator.opacity(0.45), lineWidth: 1)
    )
  }
}

struct SpeakerModePill: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    let real = model.realSpeakerDiarizationIsReady

    Label(
      real ? "Real" : "Debug / Missing",
      systemImage: real ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    )
    .font(.caption.weight(.semibold))
    .foregroundStyle(real ? .green : .orange)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background((real ? Color.green : Color.orange).opacity(0.12))
    .clipShape(Capsule())
  }
}

private struct HuggingFaceTokenSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Hugging Face Token", systemImage: "key.fill")
            .font(.headline)

          Spacer()

          Label(
            model.hasHuggingFaceToken ? "Saved" : "Missing",
            systemImage: model.hasHuggingFaceToken
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(model.hasHuggingFaceToken ? .green : .orange)
        }

        Text(
          "Required for pyannote speaker diarization models. The token is saved in macOS Keychain, not UserDefaults."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        SecureField("Paste Hugging Face token", text: $model.huggingFaceTokenDraft)
          .textFieldStyle(.roundedBorder)

        HStack {
          Button("Save Token") {
            model.saveHuggingFaceToken()
          }
          .disabled(
            model.huggingFaceTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          Button("Clear Token") {
            model.clearHuggingFaceToken()
          }
          .disabled(!model.hasHuggingFaceToken)

          Spacer()

          Button("Get Token") {
            model.openHuggingFaceTokenPage()
          }
        }

        HStack {
          Button("Open pyannote diarization model") {
            model.openPyannoteDiarizationModelPage()
          }

          Button("Open pyannote segmentation model") {
            model.openPyannoteSegmentationModelPage()
          }
        }

        if let status = model.huggingFaceTokenStatusText {
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(
          "Before testing, accept the required pyannote model conditions on Hugging Face, then create a read token."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Diarization Credentials", systemImage: "lock.shield")
    }
  }
}

struct SpeakerSettingsView: View {
  @Bindable var model: TranscriptionViewModel
  @State private var showingAdvancedDiarizer = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SpeakerWorkflowStatusCard(model: model)

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          if model.isUsingDebugSpeakerLabels {
            Text(
              "Speaker labels are in debug mode. Debug mode does not identify real voices. It only creates fake Speaker labels so the UI can be tested. To identify real speakers, save a Hugging Face token and configure a diarization executable below."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }

          Label(
            model.speakerBackendStatusText,
            systemImage: model.realSpeakerDiarizationIsReady
              ? "checkmark.circle.fill"
              : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(model.realSpeakerDiarizationIsReady ? .green : .orange)
          .font(.caption.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)

          Toggle(
            "Label speakers after transcription",
            isOn: Binding(
              get: { model.speakerDiarizationEnabled },
              set: { model.setSpeakerDiarizationEnabled($0) }
            )
          )
          .toggleStyle(.switch)
          .disabled(model.liveCaptureShowsRecordingChrome)

          Stepper(
            "Expected speakers: \(model.expectedSpeakerCount)",
            value: Binding(
              get: { model.expectedSpeakerCount },
              set: { model.setExpectedSpeakerCount($0) }
            ),
            in: 1...8
          )
          .disabled(model.liveCaptureShowsRecordingChrome)

          Toggle(
            "Preview speaker labels while recording",
            isOn: $model.liveSpeakerDiarizationEnabled
          )
          .toggleStyle(.switch)
          .disabled(
            !model.speakerDiarizationEnabled
              || !model.realSpeakerDiarizationIsReady
              || model.liveCaptureShowsRecordingChrome
          )

          Text(
            "Live speaker labels are provisional. Final labels always replace them after Stop & Transcribe. With Live Preview off, labels appear only after that final pass."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          Text("Speaker labels are applied after Stop & Transcribe.")
            .font(.caption)
            .foregroundStyle(.secondary)

          #if DEBUG
            HStack(alignment: .center, spacing: 10) {
              Button("Run with fake debug speakers") {
                model.setSpeakerDiarizationEnabled(true)
                model.diarizeSelectedSession()
              }
              .disabled(model.selectedSessionID == nil || !model.isUsingDebugSpeakerLabels)
              .help(
                "Uses the DEBUG fake diarizer only when no real executable is configured. Not real voice detection."
              )
            }
          #endif
        }
        .padding(.vertical, 6)
      } label: {
        Label("Speaker Labels", systemImage: "person.2.wave.2")
      }

      HuggingFaceTokenSettingsView(model: model)

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            TextField("Path to diarization executable", text: $model.speakerDiarizerCommandPath)
              .textFieldStyle(.roundedBorder)

            Button("Choose…") {
              model.chooseSpeakerDiarizerExecutable()
            }
          }

          HStack {
            Button("Test Real Diarizer") {
              model.testSpeakerDiarizerOnSelectedSession()
            }
            .disabled(model.selectedSessionID == nil || !model.realSpeakerDiarizationIsReady)

            Button("Detect Speakers for Selected Recording") {
              model.setSpeakerDiarizationEnabled(true)
              model.diarizeSelectedSession()
            }
            .disabled(model.selectedSessionID == nil || !model.realSpeakerDiarizationIsReady)
          }

          Text(model.realSpeakerDiarizationSetupText)
            .font(.caption)
            .foregroundStyle(model.realSpeakerDiarizationIsReady ? .green : .orange)
        }
        .padding(.vertical, 6)
      } label: {
        Label("Real Diarization Backend", systemImage: "waveform.and.person.filled")
      }

      DisclosureGroup("Advanced: executable output contract", isExpanded: $showingAdvancedDiarizer)
      {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "The diarization tool must read `--audio` and optional `--speakers`, and print SpeakerTurn JSON to stdout only."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 6) {
            Text("Expected command shape:")
              .font(.caption.weight(.semibold))

            Text("/path/to/notestream-diarize --audio recording.caf --speakers 5")
              .font(.caption.monospaced())
              .textSelection(.enabled)
              .padding(8)
              .background(AppSurface.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("The tool must print SpeakerTurn JSON to stdout.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Expected JSON output:")
              .font(.caption.weight(.semibold))

            Text(
              """
              [
                { "startTime": 0.0, "endTime": 3.2, "speakerID": "speaker_1", "confidence": 0.91 },
                { "startTime": 3.2, "endTime": 8.5, "speakerID": "speaker_2", "confidence": 0.88 }
              ]
              """
            )
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(8)
            .background(AppSurface.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }

          Text(model.speakerDiarizerModeText)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
      }
    }
  }
}
