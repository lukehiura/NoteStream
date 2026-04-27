import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func setSpeakerDiarizationEnabled(_ enabled: Bool) {
    if case .startingRecording = uiState {
      speakerDiarizationStatusText =
        "Speaker setting changes apply after the current recording."
      return
    }

    if case .recording = uiState {
      speakerDiarizationStatusText =
        "Speaker setting changes apply after the current recording."
      return
    }

    speakerDiarizationEnabled = enabled

    if !enabled {
      liveSpeakerDiarizationEnabled = false
    }

    if enabled && expectedSpeakerCount < 2 {
      expectedSpeakerCount = 2
    }

    speakerDiarizationStatusText =
      enabled
      ? speakerSetupStatusText
      : "Speaker detection is off."
  }

  func setExpectedSpeakerCount(_ count: Int) {
    expectedSpeakerCount = max(1, min(8, count))
  }

  func resetSpeakerPreferencesForDebug() {
    UserDefaults.standard.removeObject(forKey: "speakerDiarizationEnabled")
    UserDefaults.standard.removeObject(forKey: "expectedSpeakerCount")
    UserDefaults.standard.removeObject(forKey: "liveSpeakerDiarizationEnabled")
    #if DEBUG
      speakerDiarizationEnabled = true
    #else
      speakerDiarizationEnabled = false
    #endif
    expectedSpeakerCount = 2
    liveSpeakerDiarizationEnabled = false
    speakerDiarizationStatusText = speakerSetupStatusText
  }

  func chooseSpeakerDiarizerExecutable() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Choose diarization executable"

    if panel.runModal() == .OK, let url = panel.url {
      speakerDiarizerCommandPath = url.path
      speakerDiarizationStatusText = speakerSetupStatusText
    }
  }

  func chooseNotesSummarizerExecutable() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Choose notes summarizer executable"

    if panel.runModal() == .OK, let url = panel.url {
      notesSummarizerCommandPath = url.path
      llmProvider = .externalExecutable
      notesStatusText =
        notesSummarizer == nil ? "Notes summarizer not configured." : "Notes summarizer configured."
    }
  }

  func saveLLMAPIKey() {
    let cleaned = llmAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleaned.isEmpty else {
      notesStatusText = "API key is empty."
      return
    }

    do {
      try KeychainStore.save(
        cleaned,
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )

      llmAPIKeyDraft = ""
      notesStatusText = "API key saved."
      rebuildNotesSummarizer()
    } catch {
      notesStatusText = "Failed to save API key: \(String(describing: error))"
    }
  }

  func clearLLMAPIKey() {
    KeychainStore.delete(
      service: "NoteStream",
      account: "llm.\(llmProvider.rawValue)"
    )

    notesStatusText = "API key cleared."
    rebuildNotesSummarizer()
  }

  func saveHuggingFaceToken() {
    let cleaned = huggingFaceTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleaned.isEmpty else {
      huggingFaceTokenStatusText = "Hugging Face token is empty."
      return
    }

    do {
      try DiarizationCredentialStore.saveHuggingFaceToken(cleaned)
      huggingFaceTokenDraft = ""
      huggingFaceTokenStatusText = "Hugging Face token saved."
      rebuildSpeakerDiarizer()
    } catch {
      huggingFaceTokenStatusText =
        "Failed to save Hugging Face token: \(error.localizedDescription)"
    }
  }

  func clearHuggingFaceToken() {
    DiarizationCredentialStore.clearHuggingFaceToken()
    huggingFaceTokenDraft = ""
    huggingFaceTokenStatusText = "Hugging Face token cleared."
    rebuildSpeakerDiarizer()
  }

  func openHuggingFaceTokenPage() {
    guard let url = URL(string: "https://huggingface.co/settings/tokens") else { return }
    OpenExternalURL.open(url)
  }

  func openPyannoteDiarizationModelPage() {
    guard let url = URL(string: "https://huggingface.co/pyannote/speaker-diarization-3.1") else {
      return
    }
    OpenExternalURL.open(url)
  }

  func openPyannoteSegmentationModelPage() {
    guard let url = URL(string: "https://huggingface.co/pyannote/segmentation-3.0") else { return }
    OpenExternalURL.open(url)
  }

  func useRecommendedLocalLLMForThisMac() {
    llmProvider = .ollama
    llmBaseURL = "http://localhost:11434"
    useCustomLLMModelName = false
    localLLMPreset = .auto
    llmModelName = Self.defaultLocalModelName()
    let tag = llmModelName
    localLLMModelStatusText =
      "Recommended local model set to \(tag). Pull it before use if it is not installed."
    notesStatusText =
      "Recommended local model set to \(tag). Run: ollama pull \(tag) if it is not installed."
    refreshAvailableLocalLLMModels()
  }

  func refreshAvailableLocalLLMModels() {
    guard llmProvider == .ollama else {
      availableLocalLLMModels = []
      localLLMModelStatusText = "Model discovery is only available for Local Ollama."
      return
    }

    guard let ollamaModelClient else {
      localLLMModelStatusText = "Ollama client is not configured."
      return
    }

    isRefreshingLocalLLMModels = true
    localLLMModelStatusText = "Checking local Ollama models…"

    Task {
      do {
        let models = try await ollamaModelClient.listLocalModels()

        await MainActor.run {
          self.availableLocalLLMModels = models
          self.isRefreshingLocalLLMModels = false

          if models.isEmpty {
            self.localLLMModelStatusText =
              "No local Ollama models found. Pull a model first or type a model name."
          } else {
            self.localLLMModelStatusText =
              "Found \(models.count) local model\(models.count == 1 ? "" : "s")."
          }

          if !models.isEmpty,
            !self.useCustomLLMModelName,
            !models.contains(where: { $0.name == self.llmModelName })
          {
            self.llmModelName = models[0].name
          }
        }
      } catch {
        await MainActor.run {
          self.availableLocalLLMModels = []
          self.isRefreshingLocalLLMModels = false
          self.localLLMModelStatusText =
            "Could not reach Ollama at \(self.llmBaseURL). Is it running? \(String(describing: error))"
        }
      }
    }
  }

  func pullRecommendedLocalLLMModel() {
    pullLocalLLMModel(Self.recommendedOllamaModelForThisMac())
  }

  func pullSelectedLocalLLMModel() {
    let trimmed = llmModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      pullLocalLLMModel(effectiveOllamaModelName)
    } else {
      pullLocalLLMModel(trimmed)
    }
  }

  func pullLocalLLMModel(_ modelName: String) {
    guard llmProvider == .ollama else {
      localLLMModelStatusText = "Pull is only available for Local Ollama."
      return
    }

    let cleaned = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      localLLMModelStatusText = "Model name is empty."
      return
    }

    guard let ollamaModelClient else {
      localLLMModelStatusText = "Ollama client is not configured."
      return
    }

    localLLMModelStatusText = "Pulling \(cleaned)… This may take a while."

    Task {
      do {
        try await ollamaModelClient.pullModel(cleaned)

        await MainActor.run {
          self.llmModelName = cleaned
          self.useCustomLLMModelName = false
          self.localLLMModelStatusText = "Pulled \(cleaned)."
          self.refreshAvailableLocalLLMModels()
        }
      } catch {
        await MainActor.run {
          self.localLLMModelStatusText =
            "Failed to pull \(cleaned): \(String(describing: error))"
        }
      }
    }
  }

  /// Memory-based default Ollama tag for new installs and the **Auto** preset.
  static func recommendedOllamaModelForThisMac() -> String {
    let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    switch memoryGB {
    case ..<12:
      return "llama3.2:3b"
    case 12..<24:
      return "gemma3:4b"
    case 24..<36:
      return "qwen3.5:9b"
    case 36..<48:
      return "gemma3:12b"
    default:
      return "gemma3:27b"
    }
  }

  static func defaultLocalModelName() -> String {
    recommendedOllamaModelForThisMac()
  }
}
