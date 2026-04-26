import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SettingsRow<Content: View>: View {
  let label: String
  @ViewBuilder var content: Content

  var body: some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)

      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct CompactSettingRow<Content: View>: View {
  let label: String
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Text(label)
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)

      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct ProviderStatusPill: View {
  let text: String
  let systemImage: String
  let isReady: Bool

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(isReady ? .green : .secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background((isReady ? Color.green : Color.secondary).opacity(0.12))
      .clipShape(Capsule())
  }
}

struct DisabledProviderHelp: View {
  var body: some View {
    Text(
      "Choose a provider to enable AI summaries. Local Ollama runs on this Mac. Cloud providers require API keys."
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct OllamaSettingsView: View {
  @Bindable var model: TranscriptionViewModel
  @State private var showHardwareTiers = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
        SettingsRow(label: "Local preset") {
          Picker("Local preset", selection: $model.localLLMPreset) {
            ForEach(LocalLLMPreset.allCases) { preset in
              Text(preset.title).tag(preset)
            }
          }
          .labelsHidden()
          .frame(width: 240)
        }

        SettingsRow(label: "Active model") {
          HStack(spacing: 8) {
            Text(model.effectiveOllamaModelName)
              .font(.callout.monospaced())
              .textSelection(.enabled)

            Button("Use recommended") {
              model.useRecommendedLocalLLMForThisMac()
            }
          }
        }

        if model.localLLMPreset == .custom {
          SettingsRow(label: "Model name") {
            TextField("Example: gemma3:4b", text: $model.llmModelName)
              .textFieldStyle(.roundedBorder)
          }
        }

        SettingsRow(label: "Base URL") {
          TextField("http://localhost:11434", text: $model.llmBaseURL)
            .textFieldStyle(.roundedBorder)
        }
      }

      DisclosureGroup("Hardware recommendations", isExpanded: $showHardwareTiers) {
        HardwareTierTable()
          .padding(.top, 8)
      }

      LocalOllamaSetupCard(model: model)
    }
  }
}

struct HardwareTierTable: View {
  private let rows: [HardwareTier] = [
    .init(
      memory: "8 GB", recommended: "llama3.2:3b", better: "gemma3:1b", notes: "Basic summaries"),
    .init(memory: "16 GB", recommended: "gemma3:4b", better: "qwen3.5:4b", notes: "Good default"),
    .init(memory: "24 GB", recommended: "qwen3.5:9b", better: "gemma3:12b", notes: "Better titles"),
    .init(
      memory: "32 to 36 GB", recommended: "gemma3:12b", better: "qwen3.5:9b",
      notes: "Strong local quality"),
    .init(
      memory: "48 GB+", recommended: "gemma3:27b", better: "qwen3.5:27b", notes: "Long recordings"),
    .init(memory: "64 GB+", recommended: "qwen3.5:27b", better: "larger MoE", notes: "Power users"),
  ]

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        TableHeader("Memory", width: 90)
        TableHeader("Recommended", width: 130)
        TableHeader("Better", width: 120)
        TableHeader("Notes", width: nil)
      }
      .padding(.vertical, 6)

      Divider()

      ForEach(rows) { row in
        HStack(alignment: .top) {
          TableCell(row.memory, width: 90, monospaced: true)
          TableCell(row.recommended, width: 130, monospaced: true)
          TableCell(row.better, width: 120, monospaced: true)
          TableCell(row.notes, width: nil)
        }
        .padding(.vertical, 7)

        if row.id != rows.last?.id {
          Divider()
        }
      }
    }
    .padding(10)
    .background(.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(.secondary.opacity(0.14))
    }
  }
}

struct HardwareTier: Identifiable {
  var id: String { memory }
  let memory: String
  let recommended: String
  let better: String
  let notes: String
}

struct TableHeader: View {
  let text: String
  let width: CGFloat?

  init(_ text: String, width: CGFloat?) {
    self.text = text
    self.width = width
  }

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(width: width, alignment: .leading)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
  }
}

struct TableCell: View {
  let text: String
  let width: CGFloat?
  let monospaced: Bool

  init(_ text: String, width: CGFloat?, monospaced: Bool = false) {
    self.text = text
    self.width = width
    self.monospaced = monospaced
  }

  var body: some View {
    Text(text)
      .font(monospaced ? .caption.monospaced() : .caption)
      .foregroundStyle(.primary)
      .frame(width: width, alignment: .leading)
      .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
  }
}

struct LocalOllamaSetupCard: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Local Ollama setup", systemImage: "desktopcomputer")
          .font(.callout.weight(.semibold))

        Spacer()

        Button("Test Ollama") {
          model.testNotesSummarizer()
        }
      }

      Text("Install Ollama, pull the active model, then test the summarizer.")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Text("ollama pull \(model.effectiveOllamaModelName)")
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .background(.black.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 6))

        Button {
          ClipboardExporter.copyToClipboard(text: "ollama pull \(model.effectiveOllamaModelName)")
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .help("Copy command")
      }

      Text("Local Ollama does not require an API key. It must be running at \(model.llmBaseURL).")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

struct CloudLLMSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  let providerName: String
  let modelPlaceholder: String
  let baseURLVisible: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
        SettingsRow(label: "Model name") {
          TextField(modelPlaceholder, text: $model.llmModelName)
            .textFieldStyle(.roundedBorder)
        }

        if baseURLVisible {
          SettingsRow(label: "Base URL") {
            TextField("Example: http://localhost:1234/v1", text: $model.llmBaseURL)
              .textFieldStyle(.roundedBorder)
          }
        }

        SettingsRow(label: "API key") {
          HStack {
            SecureField(apiKeyPlaceholder, text: $model.llmAPIKeyDraft)
              .textFieldStyle(.roundedBorder)

            Button("Save") {
              model.saveLLMAPIKey()
            }

            Button("Clear") {
              model.clearLLMAPIKey()
            }
          }
        }
      }

      Text(helpText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var apiKeyPlaceholder: String {
    switch model.llmProvider {
    case .openAI:
      return "OpenAI API key"
    case .anthropic:
      return "Anthropic API key"
    case .openAICompatible:
      return "API key, if required"
    default:
      return "\(providerName) API key"
    }
  }

  private var helpText: String {
    if baseURLVisible {
      return
        "Use this for LM Studio, OpenRouter, LocalAI, vLLM, or another OpenAI-compatible server."
    }

    return
      "\(providerName) requires an API key. Keys are saved in macOS Keychain, not UserDefaults."
  }
}

struct ExternalExecutableSettingsView: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
        SettingsRow(label: "Executable") {
          HStack {
            TextField(
              "Path to notes summarizer executable", text: $model.notesSummarizerCommandPath
            )
            .textFieldStyle(.roundedBorder)

            Button("Choose…") {
              model.chooseNotesSummarizerExecutable()
            }
          }
        }
      }

      Text(
        "Advanced mode. NoteStream sends JSON to stdin and expects NotesSummary JSON from stdout."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}
