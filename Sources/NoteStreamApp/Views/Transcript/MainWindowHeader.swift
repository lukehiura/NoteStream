import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowHeader: View {
  @Bindable var model: TranscriptionViewModel
  let selectedSession: LectureSession?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("NoteStream")
            .font(.title2.weight(.semibold))

          if let status = model.statusText {
            Text(status)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer()

        if model.isBusy {
          ProgressView()
            .controlSize(.small)
        }

        if model.liveCaptureShowsRecordingChrome {
          Button("Stop & Transcribe") {
            model.stopAndTranscribeRecording()
          }
          .buttonStyle(.borderedProminent)
        }

        ModelPickerControl(model: model, compact: true)

        Button {
          model.setSpeakerDiarizationEnabled(!model.speakerDiarizationEnabled)
        } label: {
          Label(
            model.speakerToolbarTitle,
            systemImage: model.speakerDiarizationEnabled ? "person.2.wave.2.fill" : "person.2.slash"
          )
        }
        .buttonStyle(.bordered)
        .tint(model.speakerDiarizationEnabled ? .blue : .secondary)
        .help(
          model.isUsingDebugSpeakerLabels
            ? "DEBUG: speaker labels are fake test data. Configure a real diarizer executable in Settings → Speakers to detect real voices."
            : model.liveSpeakerDiarizationEnabled && model.realSpeakerDiarizationIsReady
              ? "Provisional speaker labels update during recording when a real diarizer is configured. Final labels are recalculated after Stop & Transcribe."
              : "Turn speaker labeling on or off. Real detection requires a Hugging Face token and diarization executable in Settings → Speakers."
        )
        .disabled(model.liveCaptureShowsRecordingChrome)

        Button {
          model.openAINotesSettings()
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.bordered)
        .help("AI Notes settings")

        Button("Model…") {
          model.showingModelPanel = true
        }

        #if DEBUG
          Button("Diagnostics") {
            model.showingDiagnosticsPanel = true
          }
        #endif
      }

      if !model.allSegments.isEmpty || model.liveCaptureShowsRecordingChrome {
        SessionSummaryBar(
          title: model.selectedFileName ?? selectedSession?.title ?? "Current transcript",
          status: activeStatusLabel,
          modelName: SpeechModelDisplay.name(for: model.selectedModel),
          segmentCount: model.allSegments.count,
          duration: transcriptDurationText,
          speakerSummary: model.speakerCountDisplayText
        )
      }
    }
  }

  private var activeStatusLabel: String {
    switch model.uiState {
    case .startingRecording:
      return "Starting"
    case .recording:
      return "Recording"
    case .finalizingTranscript:
      return "Finalizing"
    case .completed:
      return "Completed"
    case .failed:
      return "Failed"
    case .transcribing:
      return "Transcribing"
    case .preparingModel:
      return "Preparing model"
    case .ready:
      return "Ready"
    case .idle:
      return "Idle"
    }
  }

  private var transcriptDurationText: String {
    TranscriptFormatting.formatDuration(model.allSegments.transcriptDuration)
  }

}
