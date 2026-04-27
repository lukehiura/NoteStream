// swiftlint:disable file_length type_body_length function_body_length
import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class TranscriptionViewModel {
  enum TranscriptionUIState: Equatable {
    case idle
    case preparingModel(String)
    case ready(String)
    case startingRecording(startedAt: Date)
    case recording(startedAt: Date)
    case transcribing(fileName: String)
    case finalizingTranscript(fileName: String)
    case completed(fileName: String)
    case failed(message: String)
  }

  /// Shown under Settings → LLM Notes when Ollama is selected (unified-memory Mac tiers).
  static let ollamaHardwareTierGuideMarkdown = """
    8GB: use the smallest fast model (e.g. tiny/base class).
    16GB: comfortable for small/medium models; avoid huge context + huge weights together.
    32GB+: larger models and longer context are more feasible; still watch thermals when recording.
    Pull only the model you need (`ollama pull <name>`) so startup stays predictable.
    """

  var selectedModel: String {
    didSet {
      UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
    }
  }
  var selectedFileName: String?
  var sessions: [LectureSession] = []
  var selectedSessionID: UUID?
  var committedSegments: [TranscriptSegment] = []
  var draftSegments: [TranscriptSegment] = []
  var liveTranscriptSegments: [TranscriptSegment] = []
  var uiState: TranscriptionUIState = .idle

  /// True while recording UI is active (disable settings that would fight live capture).
  var liveCaptureShowsRecordingChrome: Bool {
    if case .recording = uiState { return true }
    if case .startingRecording = uiState { return true }
    return false
  }

  var showingError: Bool = false
  var errorMessage: String?
  var showingPermissionPanel: Bool = false
  var modelStatus: ModelStatus?
  var showingModelPanel: Bool = false
  var rollingFrameCount: Int = 0
  var rollingChunkCount: Int = 0
  var rollingErrorCount: Int = 0
  var rollingLastError: String?
  var lastRMS: Float = 0
  var audioHealth: AudioInputHealth = .ok

  var liveCaptureShowsBlockedAudioBanner: Bool {
    if case .recording = uiState, audioHealth == .silentSuspected { return true }
    if case .startingRecording = uiState, audioHealth == .silentSuspected { return true }
    return false
  }

  var showingDiagnosticsPanel: Bool = false
  var showingSettingsPanel: Bool = false

  /// Last-selected settings sidebar tab; `openAINotesSettings()` forces `"aiNotes"`.
  var preferredSettingsSectionRaw: String = "aiNotes"

  var showingRecoveryPanel: Bool = false
  var recoverableAudioFiles: [URL] = []

  var showingOnboarding: Bool = false

  var onboardingCompleted: Bool {
    didSet {
      UserDefaults.standard.set(onboardingCompleted, forKey: "onboardingCompleted")
    }
  }

  var speakerDiarizerCommandPath: String {
    didSet {
      UserDefaults.standard.set(speakerDiarizerCommandPath, forKey: "speakerDiarizerCommandPath")
      rebuildSpeakerDiarizer()
    }
  }

  var notesSummarizerCommandPath: String {
    didSet {
      UserDefaults.standard.set(notesSummarizerCommandPath, forKey: "notesSummarizerCommandPath")
      rebuildNotesSummarizer()
    }
  }

  var llmProvider: LLMProvider {
    didSet {
      UserDefaults.standard.set(llmProvider.rawValue, forKey: "llmProvider")
      if llmProvider == .off {
        notesSummaryEnabled = false
        liveNotesEnabled = false
      }
      rebuildNotesSummarizer()

      if llmProvider == .ollama {
        refreshAvailableLocalLLMModels()
      } else {
        availableLocalLLMModels = []
        localLLMModelStatusText = nil
        isRefreshingLocalLLMModels = false
      }
    }
  }

  var llmModelName: String {
    didSet {
      UserDefaults.standard.set(llmModelName, forKey: "llmModelName")
      rebuildNotesSummarizer()
    }
  }

  var llmBaseURL: String {
    didSet {
      UserDefaults.standard.set(llmBaseURL, forKey: "llmBaseURL")
      rebuildOllamaModelClient()
      rebuildNotesSummarizer()
      if llmProvider == .ollama {
        refreshAvailableLocalLLMModels()
      }
    }
  }

  var localLLMPreset: LocalLLMPreset {
    didSet {
      UserDefaults.standard.set(localLLMPreset.rawValue, forKey: "localLLMPreset")
      if oldValue != localLLMPreset {
        applyLocalLLMPresetToStoredModelName()
      }
      rebuildNotesSummarizer()
      if llmProvider == .ollama {
        refreshAvailableLocalLLMModels()
      }
    }
  }

  var availableLocalLLMModels: [LocalLLMModel] = []
  var isRefreshingLocalLLMModels: Bool = false
  var localLLMModelStatusText: String?

  var useCustomLLMModelName: Bool {
    didSet {
      UserDefaults.standard.set(useCustomLLMModelName, forKey: "useCustomLLMModelName")
    }
  }

  var llmAPIKeyDraft: String = ""

  var ollamaModelClient: OllamaModelClient?

  /// Ollama model tag for API calls: prefers a non-empty `llmModelName` (picker or typed), else preset tier / memory.
  var effectiveOllamaModelName: String {
    let trimmed = llmModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return trimmed
    }
    switch localLLMPreset {
    case .auto:
      return Self.recommendedOllamaModelForThisMac()
    case .smallMac:
      return "llama3.2:3b"
    case .balancedMac:
      return "gemma3:4b"
    case .highQualityMac:
      return "gemma3:12b"
    case .custom:
      return Self.recommendedOllamaModelForThisMac()
    }
  }

  var deleteAudioAfterTranscription: Bool {
    didSet {
      UserDefaults.standard.set(
        deleteAudioAfterTranscription, forKey: "deleteAudioAfterTranscription")
    }
  }

  var playback = PlaybackController()

  var speakerDiarizationEnabled: Bool {
    didSet {
      UserDefaults.standard.set(speakerDiarizationEnabled, forKey: "speakerDiarizationEnabled")
    }
  }

  var expectedSpeakerCount: Int {
    didSet {
      UserDefaults.standard.set(expectedSpeakerCount, forKey: "expectedSpeakerCount")
    }
  }

  var speakerDiarizationStatusText: String?

  var huggingFaceTokenDraft: String = ""
  var huggingFaceTokenStatusText: String?

  var hasHuggingFaceToken: Bool {
    DiarizationCredentialStore.readHuggingFaceToken()?.isEmpty == false
  }

  var realDiarizerExecutableIsSet: Bool {
    let path = speakerDiarizerCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
    return !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
  }

  var realSpeakerDiarizationIsReady: Bool {
    realDiarizerExecutableIsSet && hasHuggingFaceToken
  }

  var realSpeakerDiarizationSetupText: String {
    if !realDiarizerExecutableIsSet && !hasHuggingFaceToken {
      return "Add a Hugging Face token and choose a diarization executable."
    }

    if !hasHuggingFaceToken {
      return "Hugging Face token is missing."
    }

    if !realDiarizerExecutableIsSet {
      return "Diarization executable is missing."
    }

    return "Real speaker diarization is ready."
  }

  /// Provisional speaker labels during capture using rolling-window batch diarization (requires a real diarizer).
  var liveSpeakerDiarizationEnabled: Bool {
    didSet {
      UserDefaults.standard.set(
        liveSpeakerDiarizationEnabled, forKey: "liveSpeakerDiarizationEnabled")
      if !liveSpeakerDiarizationEnabled {
        stopLiveSpeakerDiarizationSync()
      }
    }
  }

  var liveSpeakerStatusText: String?
  var isLiveSpeakerDiarizationActive: Bool = false

  /// Toolbar / compact label for the speaker control (distinguishes debug vs real vs off).
  var speakerToolbarTitle: String {
    if !speakerDiarizationEnabled {
      return "Speakers Off"
    }
    if speakerDiarizerIsUsingDebugPlaceholder {
      return "Debug Speakers"
    }
    if realSpeakerDiarizationIsReady {
      if liveSpeakerDiarizationEnabled {
        return "Speakers Live Preview"
      }
      return "Speakers After Stop"
    }
    return "Speakers Setup Needed"
  }

  /// Summary bar “Speakers” column: never shows a fake count as if it were real detection.
  var speakerCountDisplayText: String {
    if speakerDiarizerIsUsingDebugPlaceholder {
      return "Debug"
    }

    let ids = Set(allSegments.compactMap(\.speakerID))
    if !ids.isEmpty {
      return "\(ids.count)"
    }

    if speakerDiarizationEnabled {
      if liveCaptureShowsRecordingChrome {
        return "After recording"
      }
      return realSpeakerDiarizationIsReady ? "Pending" : "Setup"
    }

    return "Off"
  }

  /// True when the DEBUG fake diarizer is active (not real voice diarization).
  var isUsingDebugSpeakerLabels: Bool {
    speakerDiarizerIsUsingDebugPlaceholder
  }

  var speakerBackendStatusText: String {
    speakerDiarizerModeText
  }

  var speakerSetupStatusText: String {
    if !speakerDiarizationEnabled {
      return "Speaker labels are off."
    }

    if speakerDiarizerIsUsingDebugPlaceholder {
      return "Debug speaker mode is active. Labels are fake test labels."
    }

    if realSpeakerDiarizationIsReady {
      return
        "Real speaker diarization is ready. Speaker labels will be applied after Stop & Transcribe."
    }

    return realSpeakerDiarizationSetupText
  }

  var speakerDiarizerModeText: String {
    if realSpeakerDiarizationIsReady {
      return "Real speaker diarization backend configured."
    }

    #if DEBUG
      if speakerDiarizerIsUsingDebugPlaceholder {
        return "Debug speaker mode. Labels are fake test labels."
      }
    #endif

    return realSpeakerDiarizationSetupText
  }

  var notesMarkdown: String = ""
  var generatedTitle: String?
  var notesStatusText: String?

  var topicTimeline: [TopicTimelineItem] = []

  let liveNotes = LiveNotesCoordinator()

  /// Timestamp of the last successful live-notes refresh while recording.
  var liveNotesLastUpdatedAt: Date? { liveNotes.lastUpdatedAt }
  /// Live-notes-only status (waiting, skipped, updated time); not used for post-stop final notes.
  var liveNotesStatusText: String? {
    get { liveNotes.statusText }
    set { liveNotes.statusText = newValue }
  }
  var isGeneratingLiveNotes: Bool { liveNotes.isGenerating }

  var questionAnswerer: HTTPRecordingQuestionAnswerer?
  var askQuestionText: String = ""
  var askAnswerMarkdown: String = ""
  var askStatusText: String?
  var isAnsweringQuestion: Bool = false

  var canAskRecording: Bool {
    questionAnswerer != nil
      && !allSegments.isEmpty
      && !askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isAnsweringQuestion
      && !isBusy
  }

  var onboardingWizardStatusLine: String {
    if let n = notesStatusText, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return n
    }
    switch uiState {
    case .recording, .startingRecording:
      return "Recording…"
    case .transcribing, .finalizingTranscript:
      return "Processing…"
    default:
      return "Ready"
    }
  }

  var notesSummarizerIsConfigured: Bool {
    guard notesSummarizer != nil else { return false }
    switch llmProvider {
    case .off:
      return false
    case .ollama:
      return true
    case .openAI, .anthropic:
      return hasLLMAPIKey
    case .openAICompatible:
      let trimmed = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      return URL(string: trimmed) != nil && !trimmed.isEmpty
    case .externalExecutable:
      let path = notesSummarizerCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
      return !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }
  }

  var hasLLMAPIKey: Bool {
    KeychainStore.read(
      service: "NoteStream",
      account: "llm.\(llmProvider.rawValue)"
    )?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  var llmProviderStatusText: String {
    switch llmProvider {
    case .off:
      return "LLM notes are off."
    case .ollama:
      return "Uses local Ollama. No API key required. Make sure Ollama is running."
    case .openAI:
      return hasLLMAPIKey ? "OpenAI key is saved." : "OpenAI key is missing."
    case .anthropic:
      return hasLLMAPIKey ? "Anthropic key is saved." : "Anthropic key is missing."
    case .openAICompatible:
      return hasLLMAPIKey
        ? "API key is saved (optional for some servers)."
        : "No API key saved. Add one if your compatible endpoint requires authentication."
    case .externalExecutable:
      return notesSummarizerCommandPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "External summarizer path is missing."
        : "External summarizer path is set."
    }
  }

  var canRegenerateNotes: Bool {
    selectedSessionID != nil
      && notesSummaryEnabled
      && notesSummarizerIsConfigured
      && !allSegments.isEmpty
      && !isBusy
  }

  /// Explains whether notes regeneration is available (toolbar help and empty state).
  var notesSetupStatusText: String {
    if llmProvider == .off {
      return "LLM notes provider is set to Off. Choose a provider in Settings to enable notes."
    }

    if !notesSummaryEnabled {
      return
        "Notes summary is off. Turn on “Auto-generate notes after recording” in Settings, or use Enable AI Notes in the Notes panel."
    }

    if notesSummarizer == nil {
      switch llmProvider {
      case .off:
        return "LLM notes provider is Off."
      case .ollama:
        return
          "Ollama summarizer is not ready. Check the base URL and that Ollama is running with the selected model."
      case .openAI:
        return hasLLMAPIKey
          ? "Summarizer is not initialized."
          : "Add an OpenAI API key in Settings and save it to Keychain."
      case .anthropic:
        return hasLLMAPIKey
          ? "Summarizer is not initialized."
          : "Add an Anthropic API key in Settings and save it to Keychain."
      case .openAICompatible:
        return "Set a valid base URL (e.g. LM Studio or OpenRouter) in Settings."
      case .externalExecutable:
        return "Choose an executable summarizer script, or switch to a built-in provider."
      }
    }

    if allSegments.isEmpty {
      return "No transcript is available to summarize."
    }

    if isBusy {
      return "Finish the current operation before regenerating notes."
    }

    return "Notes summarizer is ready."
  }

  var notesSummaryEnabled: Bool {
    didSet {
      UserDefaults.standard.set(notesSummaryEnabled, forKey: "notesSummaryEnabled")
      if isRecording {
        maybeUpdateLiveNotes()
      }
    }
  }

  var autoRenameRecordingsWithAI: Bool {
    didSet {
      UserDefaults.standard.set(autoRenameRecordingsWithAI, forKey: "autoRenameRecordingsWithAI")
    }
  }

  var liveNotesEnabled: Bool {
    didSet {
      UserDefaults.standard.set(liveNotesEnabled, forKey: "liveNotesEnabled")
      if liveNotesEnabled {
        maybeUpdateLiveNotes()
      } else {
        cancelLiveNotesTasks()
        liveNotesStatusText = nil
      }
    }
  }

  var liveNotesIntervalMinutes: Int {
    didSet {
      UserDefaults.standard.set(liveNotesIntervalMinutes, forKey: "liveNotesIntervalMinutes")
      if isRecording {
        maybeUpdateLiveNotes()
      }
    }
  }

  var isApplyingNotesFormatPreset: Bool = false

  var notesFormatPreset: NotesFormatPreset {
    didSet {
      UserDefaults.standard.set(notesFormatPreset.rawValue, forKey: "notesFormatPreset")

      if notesFormatPreset != .custom {
        applyNotesFormatPreset(notesFormatPreset)
      }
    }
  }

  var notesDetailLevel: NotesDetailLevel {
    didSet {
      UserDefaults.standard.set(notesDetailLevel.rawValue, forKey: "notesDetailLevel")
      markNotesFormatAsCustom()
    }
  }

  var notesTone: NotesTone {
    didSet {
      UserDefaults.standard.set(notesTone.rawValue, forKey: "notesTone")
      markNotesFormatAsCustom()
    }
  }

  var notesLanguage: NotesLanguage {
    didSet {
      UserDefaults.standard.set(notesLanguage.rawValue, forKey: "notesLanguage")
    }
  }

  var liveNotesDetailLevel: NotesDetailLevel {
    didSet {
      UserDefaults.standard.set(liveNotesDetailLevel.rawValue, forKey: "liveNotesDetailLevel")
    }
  }

  var notesCustomInstructions: String {
    didSet {
      UserDefaults.standard.set(notesCustomInstructions, forKey: "notesCustomInstructions")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesSummary: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesSummary, forKey: "includeNotesSummary")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesKeyPoints: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesKeyPoints, forKey: "includeNotesKeyPoints")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesActionItems: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesActionItems, forKey: "includeNotesActionItems")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesOpenQuestions: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesOpenQuestions, forKey: "includeNotesOpenQuestions")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesDecisions: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesDecisions, forKey: "includeNotesDecisions")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesTopicTimeline: Bool {
    didSet {
      UserDefaults.standard.set(includeNotesTopicTimeline, forKey: "includeNotesTopicTimeline")
      markNotesFormatAsCustom()
    }
  }

  var includeNotesSpeakerHighlights: Bool {
    didSet {
      UserDefaults.standard.set(
        includeNotesSpeakerHighlights, forKey: "includeNotesSpeakerHighlights")
      markNotesFormatAsCustom()
    }
  }

  var liveNotesMinimumCharacters: Int {
    didSet {
      UserDefaults.standard.set(liveNotesMinimumCharacters, forKey: "liveNotesMinimumCharacters")
    }
  }

  var notesGenerationPreferences: NotesGenerationPreferences {
    NotesGenerationPreferences(
      detailLevel: notesDetailLevel,
      tone: notesTone,
      language: notesLanguage,
      sections: NotesSectionPreferences(
        summary: includeNotesSummary,
        keyPoints: includeNotesKeyPoints,
        actionItems: includeNotesActionItems,
        openQuestions: includeNotesOpenQuestions,
        decisions: includeNotesDecisions,
        topicTimeline: includeNotesTopicTimeline,
        speakerHighlights: includeNotesSpeakerHighlights
      ),
      customInstructions: notesCustomInstructions,
      liveUpdateStyle: liveNotesDetailLevel
    )
  }

  var liveNotesStatusDisplayText: String {
    if !liveNotesEnabled {
      return "Live notes are off."
    }

    if isGeneratingLiveNotes {
      return "Updating live notes…"
    }

    if let liveNotesLastUpdatedAt {
      return "Last updated \(liveNotesLastUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    return "Waiting for enough transcript text…"
  }

  var canRefreshLiveNotesNow: Bool {
    isRecording
      && liveNotesEnabled
      && notesSummaryEnabled
      && notesSummarizerIsConfigured
      && liveNotes.canRefreshNow
      && !allSegments.isEmpty
  }

  var appearanceMode: AppAppearanceMode {
    didSet {
      UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
    }
  }

  let appDiagnosticsURL: URL
  var currentSessionDiagnosticsURL: URL?
  let memoryDiagnosticsLogger: InMemoryDiagnosticsLogger
  let diagnostics: any DiagnosticsLogging

  var recentDiagnosticsEvents: [DiagnosticsEvent] = []
  var diagnosticsLevelFilter: DiagnosticsLevel?
  var diagnosticsCategoryFilter: String = ""

  var currentTask: Task<Void, Never>?
  var rollingTask: Task<Void, Never>?
  var modelPrepareTask: Task<Void, Never>?
  var startRecordingTask: Task<Void, Never>?
  var recordingStartupWatchdogTask: Task<Void, Never>?
  let transcriber: any TranscriptionEngine
  let modelManager: any ModelManaging
  let sessionStore: any SessionStore
  let recorder: any AudioRecorder
  let injectedSpeakerDiarizer: (any SpeakerDiarizing)?
  let injectedNotesSummarizer: (any NotesSummarizing)?
  var speakerDiarizer: (any SpeakerDiarizing)?
  var speakerDiarizerIsUsingDebugPlaceholder: Bool
  var notesSummarizer: (any NotesSummarizing)?
  // Live notes state is owned by `liveNotes`.
  var liveSpeakerDiarizer: (any LiveSpeakerDiarizing)?
  var liveSpeakerTurns: [SpeakerTurn] = []
  var liveDiarizationTask: Task<Void, Never>?

  /// True only while the capture UI is in the steady recording state (not starting or finalizing).
  var isRecording: Bool {
    if case .recording = uiState { return true }
    return false
  }
  var modelStatusTask: Task<Void, Never>?
  var activeRecording: RecordingSession?
  var recordingTimer: Timer?
  var now: Date = Date()

  init(
    modelManager: (any ModelManaging)? = nil,
    transcriber: (any TranscriptionEngine)? = nil,
    sessionStore: (any SessionStore)? = nil,
    recorder: (any AudioRecorder)? = nil,
    speakerDiarizer: (any SpeakerDiarizing)? = nil,
    notesSummarizer: (any NotesSummarizing)? = nil
  ) {
    let docs =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.appDiagnosticsURL =
      docs
      .appendingPathComponent("NoteStream")
      .appendingPathComponent("Diagnostics")
      .appendingPathComponent("app.jsonl")
    let memory = InMemoryDiagnosticsLogger(capacity: 1000)
    self.memoryDiagnosticsLogger = memory
    self.diagnostics = CompositeDiagnosticsLogger([
      OSLogDiagnosticsLogger(),
      FileDiagnosticsLogger(logURL: appDiagnosticsURL),
      memory,
    ])

    self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base.en"

    self.deleteAudioAfterTranscription =
      UserDefaults.standard.object(forKey: "deleteAudioAfterTranscription") as? Bool ?? false

    #if DEBUG
      self.speakerDiarizationEnabled =
        UserDefaults.standard.object(forKey: "speakerDiarizationEnabled") as? Bool ?? true
    #else
      self.speakerDiarizationEnabled =
        UserDefaults.standard.object(forKey: "speakerDiarizationEnabled") as? Bool ?? false
    #endif
    var expected = UserDefaults.standard.integer(forKey: "expectedSpeakerCount")
    if expected <= 0 { expected = 2 }
    self.expectedSpeakerCount = expected
    self.speakerDiarizationStatusText = nil

    self.liveSpeakerDiarizationEnabled =
      UserDefaults.standard.object(forKey: "liveSpeakerDiarizationEnabled") as? Bool ?? false

    self.notesSummaryEnabled =
      UserDefaults.standard.object(forKey: "notesSummaryEnabled") as? Bool ?? false
    self.autoRenameRecordingsWithAI =
      UserDefaults.standard.object(forKey: "autoRenameRecordingsWithAI") as? Bool ?? true
    self.liveNotesEnabled =
      UserDefaults.standard.object(forKey: "liveNotesEnabled") as? Bool ?? false
    let savedInterval = UserDefaults.standard.integer(forKey: "liveNotesIntervalMinutes")
    self.liveNotesIntervalMinutes = savedInterval > 0 ? savedInterval : 5

    self.notesFormatPreset =
      NotesFormatPreset(rawValue: UserDefaults.standard.string(forKey: "notesFormatPreset") ?? "")
      ?? .balanced

    self.notesDetailLevel =
      NotesDetailLevel(rawValue: UserDefaults.standard.string(forKey: "notesDetailLevel") ?? "")
      ?? .balanced

    self.notesTone =
      NotesTone(rawValue: UserDefaults.standard.string(forKey: "notesTone") ?? "")
      ?? .clean

    self.notesLanguage =
      NotesLanguage(rawValue: UserDefaults.standard.string(forKey: "notesLanguage") ?? "")
      ?? .sameAsTranscript

    self.liveNotesDetailLevel =
      NotesDetailLevel(rawValue: UserDefaults.standard.string(forKey: "liveNotesDetailLevel") ?? "")
      ?? .brief

    self.notesCustomInstructions =
      UserDefaults.standard.string(forKey: "notesCustomInstructions") ?? ""

    self.includeNotesSummary =
      UserDefaults.standard.object(forKey: "includeNotesSummary") as? Bool ?? true

    self.includeNotesKeyPoints =
      UserDefaults.standard.object(forKey: "includeNotesKeyPoints") as? Bool ?? true

    self.includeNotesActionItems =
      UserDefaults.standard.object(forKey: "includeNotesActionItems") as? Bool ?? true

    self.includeNotesOpenQuestions =
      UserDefaults.standard.object(forKey: "includeNotesOpenQuestions") as? Bool ?? true

    self.includeNotesDecisions =
      UserDefaults.standard.object(forKey: "includeNotesDecisions") as? Bool ?? false

    self.includeNotesTopicTimeline =
      UserDefaults.standard.object(forKey: "includeNotesTopicTimeline") as? Bool ?? true

    self.includeNotesSpeakerHighlights =
      UserDefaults.standard.object(forKey: "includeNotesSpeakerHighlights") as? Bool ?? false

    let savedMinimumChars = UserDefaults.standard.integer(forKey: "liveNotesMinimumCharacters")
    self.liveNotesMinimumCharacters = savedMinimumChars > 0 ? savedMinimumChars : 500

    self.onboardingCompleted =
      UserDefaults.standard.object(forKey: "onboardingCompleted") as? Bool ?? false

    let savedAppearance = UserDefaults.standard.string(forKey: "appearanceMode")
    self.appearanceMode = AppAppearanceMode(rawValue: savedAppearance ?? "") ?? .system

    let wkManager: WhisperKitModelManager
    if let modelManager, let wk = modelManager as? WhisperKitModelManager {
      wkManager = wk
    } else {
      wkManager = WhisperKitModelManager(diagnostics: diagnostics)
    }
    self.modelManager = wkManager
    if let sessionStore {
      self.sessionStore = sessionStore
    } else {
      do {
        self.sessionStore = try FileSessionStore()
      } catch {
        fatalError("Failed to initialize FileSessionStore: \(error)")
      }
    }
    self.transcriber = transcriber ?? WhisperKitTranscriptionEngine(modelManager: wkManager)
    self.recorder = recorder ?? SystemAudioRecorder(diagnostics: diagnostics)

    self.injectedSpeakerDiarizer = speakerDiarizer
    self.injectedNotesSummarizer = notesSummarizer
    self.speakerDiarizer = nil
    self.speakerDiarizerIsUsingDebugPlaceholder = false
    self.notesSummarizer = nil

    self.speakerDiarizerCommandPath =
      UserDefaults.standard.string(forKey: "speakerDiarizerCommandPath") ?? ""
    self.notesSummarizerCommandPath =
      UserDefaults.standard.string(forKey: "notesSummarizerCommandPath") ?? ""

    let savedLLMRaw = UserDefaults.standard.string(forKey: "llmProvider")
    let migratedLLMProvider: LLMProvider
    if let savedLLMRaw, let parsed = LLMProvider(rawValue: savedLLMRaw) {
      migratedLLMProvider = parsed
    } else {
      let legacyPath = UserDefaults.standard.string(forKey: "notesSummarizerCommandPath") ?? ""
      migratedLLMProvider =
        (!legacyPath.isEmpty && FileManager.default.isExecutableFile(atPath: legacyPath))
        ? .externalExecutable
        : .ollama
    }
    self.llmProvider = migratedLLMProvider

    if let presetRaw = UserDefaults.standard.string(forKey: "localLLMPreset"),
      let preset = LocalLLMPreset(rawValue: presetRaw)
    {
      self.localLLMPreset = preset
    } else {
      self.localLLMPreset = .auto
    }

    self.llmModelName =
      UserDefaults.standard.string(forKey: "llmModelName") ?? Self.defaultLocalModelName()
    self.llmBaseURL =
      UserDefaults.standard.string(forKey: "llmBaseURL") ?? "http://localhost:11434"
    self.llmAPIKeyDraft = ""

    self.useCustomLLMModelName =
      UserDefaults.standard.object(forKey: "useCustomLLMModelName") as? Bool ?? false

    liveNotes.onNotesUpdated = { [weak self] summary, _ in
      guard let self else { return }
      self.notesMarkdown = summary.summaryMarkdown
      self.topicTimeline = summary.topicTimeline ?? self.topicTimeline
    }
    liveNotes.onError = { [weak self] error in
      self?.rollingLastError = String(describing: error)
    }

    rebuildOllamaModelClient()

    modelStatusTask = Task {
      let stream = await wkManager.statusUpdates()
      for await status in stream {
        await MainActor.run {
          self.modelStatus = status
          self.syncUIStateFromModelStatus()
        }
      }
    }

    Task {
      await reloadSessions()
      await MainActor.run {
        if self.llmProvider == .ollama {
          self.refreshAvailableLocalLLMModels()
        }
      }
    }

    if notesFormatPreset != .custom {
      applyNotesFormatPreset(notesFormatPreset)
    }

    rebuildSpeakerDiarizer()
    rebuildNotesSummarizer()

    Task {
      await diagnostics.info(
        .app,
        "app_started",
        [
          "selectedModel": selectedModel,
          "llmProvider": llmProvider.rawValue,
        ])
    }
  }
}
