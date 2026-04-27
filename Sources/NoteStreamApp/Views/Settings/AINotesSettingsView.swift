// swiftlint:disable file_length
import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct AINotesSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AINotesProviderCard(model: model)
      AINotesAutomationCard(model: model)
      NotesPresetCard(model: model)
      NotesFormatCard(model: model)
      RollingLiveNotesCard(model: model)
      NotesAdvancedInstructionsCard(model: model)

      HStack {
        Button("Reset AI Notes Defaults") {
          model.resetAINotesPreferencesToDefaults()
        }

        Spacer()

        Button("Test Summarizer") {
          model.testNotesSummarizer()
        }
        .disabled(model.llmProvider == .off)
      }
    }
  }
}

private struct AINotesProviderCard: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("AI Notes")
              .font(.headline)

            Text(
              "Choose the model provider used for summaries, titles, topic timelines, and questions."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          Spacer()

          ProviderStatusPill(
            text: providerStatusLabel,
            systemImage: providerStatusIcon,
            isReady: model.notesSummarizerIsConfigured
          )
        }

        Divider()

        CompactSettingRow(label: "Provider") {
          Picker("Provider", selection: $model.llmProvider) {
            ForEach(LLMProvider.allCases) { provider in
              Text(provider.title).tag(provider)
            }
          }
          .labelsHidden()
          .frame(width: 240)
        }

        providerSpecificSettings

        Text(model.llmProviderStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Provider", systemImage: "sparkles")
    }
  }

  @ViewBuilder
  private var providerSpecificSettings: some View {
    switch model.llmProvider {
    case .off:
      Text("Choose a provider to enable AI summaries.")
        .font(.caption)
        .foregroundStyle(.secondary)

    case .ollama:
      OllamaSettingsView(model: model)

    case .openAI:
      CloudLLMSettingsView(
        model: model,
        providerName: "OpenAI",
        modelPlaceholder: "gpt-4o-mini",
        baseURLVisible: false
      )

    case .anthropic:
      CloudLLMSettingsView(
        model: model,
        providerName: "Anthropic Claude",
        modelPlaceholder: "claude-3-5-haiku-latest",
        baseURLVisible: false
      )

    case .openAICompatible:
      CloudLLMSettingsView(
        model: model,
        providerName: "OpenAI-compatible endpoint",
        modelPlaceholder: "local-model",
        baseURLVisible: true
      )

    case .externalExecutable:
      ExternalExecutableSettingsView(model: model)
    }
  }

  private var providerStatusLabel: String {
    if model.llmProvider == .off { return "Off" }
    return model.notesSummarizerIsConfigured ? "Ready" : "Setup needed"
  }

  private var providerStatusIcon: String {
    if model.llmProvider == .off { return "pause.circle" }
    return model.notesSummarizerIsConfigured
      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
  }
}

private struct AINotesAutomationCard: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Automation")
              .font(.headline)

            Text("Control when NoteStream updates notes.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          AINotesAutomationStatusPill(model: model)
        }

        Toggle("Generate final notes after recording", isOn: $model.notesSummaryEnabled)
          .toggleStyle(.switch)
          .disabled(model.llmProvider == .off)

        Toggle("Update live notes while recording", isOn: $model.liveNotesEnabled)
          .toggleStyle(.switch)
          .disabled(!model.notesSummaryEnabled || !model.notesSummarizerIsConfigured)

        Toggle(
          "Use AI-generated titles for default recording names",
          isOn: $model.autoRenameRecordingsWithAI
        )
        .toggleStyle(.switch)
        .disabled(!model.notesSummaryEnabled || model.llmProvider == .off)

        Text("Live notes are provisional. Final notes replace them after Stop & Transcribe.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Automation", systemImage: "clock.arrow.circlepath")
    }
  }
}

private struct AINotesAutomationStatusPill: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    let text =
      !model.notesSummaryEnabled
      ? "Off"
      : model.liveNotesEnabled
        ? "Final + Live"
        : "Final only"

    let color: Color =
      !model.notesSummaryEnabled
      ? .secondary
      : model.liveNotesEnabled ? .green : .blue

    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
  }
}

private struct NotesPresetCard: View {
  @Bindable var model: TranscriptionViewModel

  private let columns = [
    GridItem(.adaptive(minimum: 150), spacing: 10)
  ]

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Note preset")
              .font(.headline)

            Text("Start with a common format, then customize if needed.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }

        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
          ForEach(NotesFormatPreset.allCases) { preset in
            NotesPresetButton(
              preset: preset,
              isSelected: model.notesFormatPreset == preset
            ) {
              model.notesFormatPreset = preset
            }
          }
        }

        Text(model.notesFormatPreset.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Preset", systemImage: "square.grid.2x2")
    }
  }
}

private struct NotesPresetButton: View {
  let preset: NotesFormatPreset
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: preset.icon)
          .frame(width: 18)

        Text(preset.title)
          .font(.callout.weight(.semibold))

        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .background(isSelected ? Color.accentColor.opacity(0.18) : AppSurface.subtleFill)
      .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct NotesFormatCard: View {
  @Bindable var model: TranscriptionViewModel
  @State private var showSections = false

  private let sectionColumns = [
    GridItem(.adaptive(minimum: 160), spacing: 10)
  ]

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        CompactSettingRow(label: "Detail") {
          Picker("Detail", selection: $model.notesDetailLevel) {
            ForEach(NotesDetailLevel.allCases) { level in
              Text(level.title).tag(level)
            }
          }
          .labelsHidden()
          .frame(width: 220)
        }

        CompactSettingRow(label: "Tone") {
          Picker("Tone", selection: $model.notesTone) {
            ForEach(NotesTone.allCases) { tone in
              Text(tone.title).tag(tone)
            }
          }
          .labelsHidden()
          .frame(width: 220)
        }

        CompactSettingRow(label: "Language") {
          Picker("Language", selection: $model.notesLanguage) {
            ForEach(NotesLanguage.allCases) { language in
              Text(language.title).tag(language)
            }
          }
          .labelsHidden()
          .frame(width: 220)
        }

        if model.notesFormatPreset == .custom {
          DisclosureGroup("Sections", isExpanded: $showSections) {
            LazyVGrid(columns: sectionColumns, alignment: .leading, spacing: 8) {
              Toggle("Summary", isOn: $model.includeNotesSummary)
              Toggle("Key Points", isOn: $model.includeNotesKeyPoints)
              Toggle("Action Items", isOn: $model.includeNotesActionItems)
              Toggle("Open Questions", isOn: $model.includeNotesOpenQuestions)
              Toggle("Decisions", isOn: $model.includeNotesDecisions)
              Toggle("Topic Timeline", isOn: $model.includeNotesTopicTimeline)
              Toggle("Speaker Highlights", isOn: $model.includeNotesSpeakerHighlights)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 8)
          }
        } else {
          HStack(spacing: 10) {
            Text("Sections are controlled by the selected preset.")
              .font(.caption)
              .foregroundStyle(.secondary)

            Spacer()

            Button("Customize…") {
              model.notesFormatPreset = .custom
              showSections = true
            }
          }
        }
      }
      .padding(.vertical, 6)
    } label: {
      Label("Note Format", systemImage: "slider.horizontal.3")
    }
  }
}

private struct RollingLiveNotesCard: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Rolling live notes")
              .font(.headline)

            Text("Periodically summarizes committed transcript text while recording.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          RollingLiveNotesPill(model: model)
        }

        Toggle("Update live notes while recording", isOn: $model.liveNotesEnabled)
          .toggleStyle(.switch)
          .disabled(!model.notesSummaryEnabled || !model.notesSummarizerIsConfigured)

        VStack(alignment: .leading, spacing: 12) {
          CompactSettingRow(label: "Refresh interval") {
            HStack(spacing: 12) {
              Slider(
                value: Binding(
                  get: { Double(model.liveNotesIntervalMinutes) },
                  set: { model.liveNotesIntervalMinutes = Int($0.rounded()) }
                ),
                in: 1...15,
                step: 1
              )
              .frame(width: 220)

              Text("\(model.liveNotesIntervalMinutes) min")
                .font(.callout.monospacedDigit())
                .frame(width: 58, alignment: .leading)
            }
          }

          CompactSettingRow(label: "Live note detail") {
            Picker("Live note detail", selection: $model.liveNotesDetailLevel) {
              ForEach(NotesDetailLevel.allCases) { level in
                Text(level.title).tag(level)
              }
            }
            .labelsHidden()
            .frame(width: 220)
          }

          CompactSettingRow(label: "Refresh after at least") {
            HStack(spacing: 12) {
              Slider(
                value: Binding(
                  get: { Double(model.liveNotesMinimumCharacters) },
                  set: { model.liveNotesMinimumCharacters = Int($0.rounded() / 100) * 100 }
                ),
                in: 200...2000,
                step: 100
              )
              .frame(width: 220)

              Text("\(model.liveNotesMinimumCharacters) chars")
                .font(.callout.monospacedDigit())
                .frame(width: 90, alignment: .leading)
            }
          }
        }
        .disabled(!model.liveNotesEnabled)

        LiveNotesProcessPreview(model: model)

        Text(
          "Recommended: 3 to 5 minutes and 500+ new characters. Shorter intervals cost more and can produce noisy updates."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Rolling Live Notes", systemImage: "arrow.triangle.2.circlepath")
    }
  }
}

private struct RollingLiveNotesPill: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    let enabled = model.liveNotesEnabled && model.notesSummaryEnabled

    Label(
      enabled ? "Enabled" : "Off", systemImage: enabled ? "checkmark.circle.fill" : "pause.circle"
    )
    .font(.caption.weight(.semibold))
    .foregroundStyle(enabled ? .green : .secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background((enabled ? Color.green : Color.secondary).opacity(0.12))
    .clipShape(Capsule())
  }
}

private struct LiveNotesProcessPreview: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Process")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        LiveNotesStep(number: "1", title: "Transcript commits")
        LiveNotesConnector()
        LiveNotesStep(number: "2", title: "\(model.liveNotesIntervalMinutes) min passes")
        LiveNotesConnector()
        LiveNotesStep(number: "3", title: "\(model.liveNotesMinimumCharacters)+ chars")
        LiveNotesConnector()
        LiveNotesStep(number: "4", title: "Notes update")
      }
    }
    .padding(10)
    .background(AppSurface.subtleFill)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct LiveNotesStep: View {
  let number: String
  let title: String

  var body: some View {
    VStack(spacing: 5) {
      Text(number)
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(Color.accentColor)
        .clipShape(Circle())

      Text(title)
        .font(.caption2)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(width: 86)
    }
  }
}

private struct LiveNotesConnector: View {
  var body: some View {
    Rectangle()
      .fill(Color.secondary.opacity(0.35))
      .frame(width: 18, height: 1)
  }
}

private struct NotesAdvancedInstructionsCard: View {
  @Bindable var model: TranscriptionViewModel
  @State private var showAdvanced = false

  var body: some View {
    GroupBox {
      DisclosureGroup("Custom instructions", isExpanded: $showAdvanced) {
        VStack(alignment: .leading, spacing: 8) {
          ZStack(alignment: .topLeading) {
            TextEditor(text: $model.notesCustomInstructions)
              .font(.body)
              .frame(minHeight: 110)
              .scrollContentBackground(.hidden)
              .padding(6)
              .background(AppSurface.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(.secondary.opacity(0.18))
              }

            if model.notesCustomInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              Text(
                "Example: Focus on decisions and tradeoffs. Keep action items at the top. Use concise bullets."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 12)
              .padding(.vertical, 12)
              .allowsHitTesting(false)
            }
          }

          HStack {
            Button("Clear") {
              model.notesCustomInstructions = ""
            }
            .disabled(
              model.notesCustomInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            Text("\(model.notesCustomInstructions.count) chars")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        .padding(.top, 10)
      }
    } label: {
      Label("Advanced Instructions", systemImage: "text.quote")
    }
  }
}
