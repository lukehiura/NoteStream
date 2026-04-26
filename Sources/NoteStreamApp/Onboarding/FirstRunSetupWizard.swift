import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI

struct FirstRunSetupWizard: View {
  @Bindable var model: TranscriptionViewModel
  @State private var selectedStep: OnboardingStep = .screenRecording

  var body: some View {
    HSplitView {
      List(OnboardingStep.allCases, selection: $selectedStep) { step in
        Label(step.title, systemImage: step.icon)
          .tag(step)
      }
      .listStyle(.sidebar)
      .frame(minWidth: 220)

      VStack(alignment: .leading, spacing: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(selectedStep.title)
              .font(.title2.weight(.semibold))

            Text(selectedStep.subtitle)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Skip") {
            model.skipOnboarding()
          }

          Button("Done") {
            model.finishOnboarding()
          }
          .buttonStyle(.borderedProminent)
        }

        Divider()

        stepBody

        Spacer()

        HStack {
          Button("Back") {
            move(-1)
          }
          .disabled(selectedIndex == 0)

          Spacer()

          Button(selectedIndex == OnboardingStep.allCases.count - 1 ? "Finish" : "Next") {
            if selectedIndex == OnboardingStep.allCases.count - 1 {
              model.finishOnboarding()
            } else {
              move(1)
            }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(20)
      .frame(minWidth: 500)
    }
  }

  @ViewBuilder
  private var stepBody: some View {
    switch selectedStep {
    case .screenRecording:
      VStack(alignment: .leading, spacing: 12) {
        Text("NoteStream needs Screen Recording permission to capture system audio.")
        HStack {
          Button("Open System Settings") {
            ScreenRecordingPermission.openSystemSettings()
          }

          Button("Check Permission") {
            Task {
              _ = await ScreenRecordingPermission.request()
              await MainActor.run {
                model.showingPermissionPanel = !ScreenRecordingPermission.hasPermission()
              }
            }
          }
        }

        Label(
          ScreenRecordingPermission.hasPermission()
            ? "Permission granted" : "Permission not confirmed",
          systemImage: ScreenRecordingPermission.hasPermission()
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(ScreenRecordingPermission.hasPermission() ? .green : .orange)
      }

    case .transcriptionModel:
      VStack(alignment: .leading, spacing: 12) {
        Text("Choose the default Whisper model.")
        ModelPickerControl(model: model)
        Text("Fast is best for quick notes. Accurate is better for final quality.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .audioTest:
      VStack(alignment: .leading, spacing: 12) {
        Text("Start a short capture and confirm frames are received.")
        HStack {
          Button("Start Test Capture") {
            model.startRecording()
          }

          Button("Stop & Transcribe") {
            model.stopAndTranscribeRecording()
          }
          .disabled(!model.liveCaptureShowsRecordingChrome)
        }

        Text("Frames: \(model.rollingFrameCount)")
        Text("RMS: \(String(format: "%.4f", model.lastRMS))")
      }

    case .aiNotes:
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Enable AI notes after recording", isOn: $model.notesSummaryEnabled)
          .toggleStyle(.switch)

        Picker("Provider", selection: $model.llmProvider) {
          ForEach(LLMProvider.allCases) { provider in
            Text(provider.title).tag(provider)
          }
        }

        if model.llmProvider == .ollama {
          Text("Local Ollama uses a model running on your Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text("Active model: \(model.effectiveOllamaModelName)")
            .font(.callout.monospaced())

          Button("Test Ollama") {
            model.testNotesSummarizer()
          }
        } else {
          Text(model.llmProviderStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

    case .speakerLabels:
      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          "Detect speaker labels after transcription",
          isOn: Binding(
            get: { model.speakerDiarizationEnabled },
            set: { model.setSpeakerDiarizationEnabled($0) }
          )
        )
        .toggleStyle(.switch)

        Stepper(
          "Expected speakers: \(model.expectedSpeakerCount)",
          value: Binding(
            get: { model.expectedSpeakerCount },
            set: { model.setExpectedSpeakerCount($0) }
          ),
          in: 1...8
        )

        Text(model.speakerSetupStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

    case .testRecording:
      VStack(alignment: .leading, spacing: 12) {
        Text("Run a 10 second recording to validate capture, transcription, and optional notes.")
        Button("Run 10 Second Test Recording") {
          model.runTenSecondTestRecording()
        }
        .buttonStyle(.borderedProminent)

        Text(model.onboardingWizardStatusLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var selectedIndex: Int {
    OnboardingStep.allCases.firstIndex(of: selectedStep) ?? 0
  }

  private func move(_ delta: Int) {
    let steps = OnboardingStep.allCases
    let next = max(0, min(steps.count - 1, selectedIndex + delta))
    selectedStep = steps[next]
  }
}
