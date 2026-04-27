import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
  func makeHTTPLLMConfig() -> HTTPNotesSummarizerConfig? {
    let trimmedModel = llmModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBase = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let storedKey = KeychainStore.read(
      service: "NoteStream",
      account: "llm.\(llmProvider.rawValue)"
    )?.trimmingCharacters(in: .whitespacesAndNewlines)

    switch llmProvider {
    case .off, .externalExecutable:
      return nil

    case .ollama:
      return HTTPNotesSummarizerConfig(
        provider: .ollama,
        model: effectiveOllamaModelName,
        baseURL: URL(string: trimmedBase),
        apiKey: nil
      )

    case .openAI, .anthropic:
      guard let key = storedKey, !key.isEmpty else { return nil }
      return HTTPNotesSummarizerConfig(
        provider: llmProvider,
        model: trimmedModel,
        baseURL: nil,
        apiKey: key
      )

    case .openAICompatible:
      guard let baseURL = URL(string: trimmedBase), !trimmedBase.isEmpty else { return nil }
      return HTTPNotesSummarizerConfig(
        provider: .openAICompatible,
        model: trimmedModel,
        baseURL: baseURL,
        apiKey: storedKey?.isEmpty == true ? nil : storedKey
      )
    }
  }

  func applyNotesFormatPreset(_ preset: NotesFormatPreset) {
    isApplyingNotesFormatPreset = true
    defer { isApplyingNotesFormatPreset = false }

    switch preset {
    case .balanced:
      notesDetailLevel = .balanced
      notesTone = .clean
      includeNotesSummary = true
      includeNotesKeyPoints = true
      includeNotesActionItems = true
      includeNotesOpenQuestions = true
      includeNotesDecisions = false
      includeNotesTopicTimeline = true
      includeNotesSpeakerHighlights = false

    case .meeting:
      notesDetailLevel = .balanced
      notesTone = .meetingMinutes
      includeNotesSummary = true
      includeNotesKeyPoints = true
      includeNotesActionItems = true
      includeNotesOpenQuestions = true
      includeNotesDecisions = true
      includeNotesTopicTimeline = true
      includeNotesSpeakerHighlights = true

    case .lecture:
      notesDetailLevel = .detailed
      notesTone = .studyNotes
      includeNotesSummary = true
      includeNotesKeyPoints = true
      includeNotesActionItems = false
      includeNotesOpenQuestions = true
      includeNotesDecisions = false
      includeNotesTopicTimeline = true
      includeNotesSpeakerHighlights = false

    case .executive:
      notesDetailLevel = .brief
      notesTone = .executive
      includeNotesSummary = true
      includeNotesKeyPoints = true
      includeNotesActionItems = true
      includeNotesOpenQuestions = true
      includeNotesDecisions = true
      includeNotesTopicTimeline = false
      includeNotesSpeakerHighlights = false

    case .study:
      notesDetailLevel = .detailed
      notesTone = .studyNotes
      includeNotesSummary = true
      includeNotesKeyPoints = true
      includeNotesActionItems = false
      includeNotesOpenQuestions = true
      includeNotesDecisions = false
      includeNotesTopicTimeline = true
      includeNotesSpeakerHighlights = true

    case .custom:
      break
    }
  }

  func markNotesFormatAsCustom() {
    guard !isApplyingNotesFormatPreset else { return }
    if notesFormatPreset != .custom {
      notesFormatPreset = .custom
    }
  }

  func resetAINotesPreferencesToDefaults() {
    notesFormatPreset = .balanced
    applyNotesFormatPreset(.balanced)

    notesLanguage = .sameAsTranscript
    notesCustomInstructions = ""
    liveNotesEnabled = false
    liveNotesIntervalMinutes = 5
    liveNotesDetailLevel = .brief
    liveNotesMinimumCharacters = 500

    notesStatusText = "AI notes preferences reset."
  }

  func rebuildOllamaModelClient() {
    let trimmed = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let url =
      URL(string: trimmed) ?? (URL(string: "http://localhost:11434") ?? URL(fileURLWithPath: "/"))
    ollamaModelClient = OllamaModelClient(baseURL: url, diagnostics: diagnostics)
  }

  func applyLocalLLMPresetToStoredModelName() {
    switch localLLMPreset {
    case .auto:
      llmModelName = ""
    case .smallMac:
      llmModelName = "llama3.2:3b"
    case .balancedMac:
      llmModelName = "gemma3:4b"
    case .highQualityMac:
      llmModelName = "gemma3:12b"
    case .custom:
      break
    }

    if localLLMPreset == .custom {
      useCustomLLMModelName = true
    } else {
      useCustomLLMModelName = false
    }
  }

  func rebuildSpeakerDiarizer() {
    if let injectedSpeakerDiarizer {
      speakerDiarizer = injectedSpeakerDiarizer
      #if DEBUG
        speakerDiarizerIsUsingDebugPlaceholder =
          (injectedSpeakerDiarizer is DebugSpeakerDiarizer)
      #else
        speakerDiarizerIsUsingDebugPlaceholder = false
      #endif
      configureLiveSpeakerDiarizerAdapter()
      return
    }

    speakerDiarizerIsUsingDebugPlaceholder = false

    let path = speakerDiarizerCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)

    if !path.isEmpty,
      FileManager.default.isExecutableFile(atPath: path)
    {
      guard let hfToken = DiarizationCredentialStore.readHuggingFaceToken(),
        !hfToken.isEmpty
      else {
        speakerDiarizer = nil
        speakerDiarizationStatusText =
          "Real speaker diarization requires a Hugging Face token."
        configureLiveSpeakerDiarizerAdapter()
        return
      }

      speakerDiarizer = ExternalJSONSpeakerDiarizer(
        executableURL: URL(fileURLWithPath: path),
        additionalEnvironment: [
          "HF_TOKEN": hfToken,
          "HUGGINGFACE_TOKEN": hfToken,
          "HUGGING_FACE_HUB_TOKEN": hfToken,
        ],
        diagnostics: diagnostics
      )

      speakerDiarizationStatusText = "Real speaker diarization configured."
      configureLiveSpeakerDiarizerAdapter()
      return
    }

    #if DEBUG
      speakerDiarizer = DebugSpeakerDiarizer()
      speakerDiarizerIsUsingDebugPlaceholder = true
      speakerDiarizationStatusText =
        "Debug speaker mode. Labels are fake until a real diarizer and Hugging Face token are configured."
    #else
      speakerDiarizer = nil
      speakerDiarizationStatusText = "No real speaker diarization backend configured."
    #endif

    configureLiveSpeakerDiarizerAdapter()
  }

  /// Wraps the batch diarizer in a rolling-window live adapter when a real (non-debug) diarizer exists.
  func configureLiveSpeakerDiarizerAdapter() {
    if let speakerDiarizer, !speakerDiarizerIsUsingDebugPlaceholder {
      liveSpeakerDiarizer = RollingWindowSpeakerDiarizer(
        batchDiarizer: speakerDiarizer,
        windowSeconds: 60,
        minIntervalSeconds: 20,
        diagnostics: diagnostics
      )
    } else {
      liveSpeakerDiarizer = nil
    }
  }

  func rebuildNotesSummarizer() {
    defer { rebuildQuestionAnswerer() }

    if let injectedNotesSummarizer {
      notesSummarizer = injectedNotesSummarizer
      return
    }

    switch llmProvider {
    case .off:
      notesSummarizer = nil

    case .externalExecutable:
      let path = notesSummarizerCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)

      if !path.isEmpty,
        FileManager.default.isExecutableFile(atPath: path)
      {
        notesSummarizer = ExternalJSONNotesSummarizer(
          executableURL: URL(fileURLWithPath: path),
          diagnostics: diagnostics
        )
      } else {
        notesSummarizer = nil
      }

    case .ollama, .openAI, .anthropic, .openAICompatible:
      if let config = makeHTTPLLMConfig() {
        notesSummarizer = HTTPNotesSummarizer(config: config, diagnostics: diagnostics)
      } else {
        notesSummarizer = nil
      }
    }

    maybeUpdateLiveNotes()
  }

  func rebuildQuestionAnswerer() {
    if let config = makeHTTPLLMConfig() {
      questionAnswerer = HTTPRecordingQuestionAnswerer(config: config)
    } else {
      questionAnswerer = nil
    }
  }
}
