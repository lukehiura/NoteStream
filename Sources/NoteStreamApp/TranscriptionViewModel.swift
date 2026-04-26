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

  private var ollamaModelClient: OllamaModelClient?

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

  /// Timestamp of the last successful live-notes refresh while recording.
  var liveNotesLastUpdatedAt: Date?
  /// Live-notes-only status (waiting, skipped, updated time); not used for post-stop final notes.
  var liveNotesStatusText: String?
  var isGeneratingLiveNotes: Bool = false

  private var questionAnswerer: HTTPRecordingQuestionAnswerer?
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

  private var isApplyingNotesFormatPreset: Bool = false

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
      && !isGeneratingLiveNotes
      && notesTask == nil
      && !allSegments.isEmpty
  }

  var appearanceMode: AppAppearanceMode {
    didSet {
      UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
    }
  }

  private let appDiagnosticsURL: URL
  private var currentSessionDiagnosticsURL: URL?
  private let memoryDiagnosticsLogger: InMemoryDiagnosticsLogger
  private let diagnostics: any DiagnosticsLogging

  var recentDiagnosticsEvents: [DiagnosticsEvent] = []
  var diagnosticsLevelFilter: DiagnosticsLevel?
  var diagnosticsCategoryFilter: String = ""

  private var currentTask: Task<Void, Never>?
  private var rollingTask: Task<Void, Never>?
  private var modelPrepareTask: Task<Void, Never>?
  private var startRecordingTask: Task<Void, Never>?
  private var recordingStartupWatchdogTask: Task<Void, Never>?
  private let transcriber: any TranscriptionEngine
  private let modelManager: any ModelManaging
  private let sessionStore: any SessionStore
  private let recorder: any AudioRecorder
  private let injectedSpeakerDiarizer: (any SpeakerDiarizing)?
  private let injectedNotesSummarizer: (any NotesSummarizing)?
  private var speakerDiarizer: (any SpeakerDiarizing)?
  private var speakerDiarizerIsUsingDebugPlaceholder: Bool
  private var notesSummarizer: (any NotesSummarizing)?
  private var notesTask: Task<Void, Never>?
  private var liveSpeakerDiarizer: (any LiveSpeakerDiarizing)?
  private var liveSpeakerTurns: [SpeakerTurn] = []
  private var liveDiarizationTask: Task<Void, Never>?
  /// Audio timeline position (seconds) of the last successful live-notes refresh.
  private var lastLiveNotesUpdateAtAudioTime: TimeInterval = 0
  /// End time in the transcript (seconds) covered by the last live-notes delta.
  private var lastSummarizedSegmentEndTime: TimeInterval = 0

  /// True only while the capture UI is in the steady recording state (not starting or finalizing).
  var isRecording: Bool {
    if case .recording = uiState { return true }
    return false
  }
  private var modelStatusTask: Task<Void, Never>?
  private var activeRecording: RecordingSession?
  private var recordingTimer: Timer?
  private var now: Date = Date()

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

  private func rebuildOllamaModelClient() {
    let trimmed = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let url =
      URL(string: trimmed) ?? (URL(string: "http://localhost:11434") ?? URL(fileURLWithPath: "/"))
    ollamaModelClient = OllamaModelClient(baseURL: url, diagnostics: diagnostics)
  }

  private func applyLocalLLMPresetToStoredModelName() {
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

  private func rebuildSpeakerDiarizer() {
    if let injectedSpeakerDiarizer {
      speakerDiarizer = injectedSpeakerDiarizer
      speakerDiarizerIsUsingDebugPlaceholder = (injectedSpeakerDiarizer is DebugSpeakerDiarizer)
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
  private func configureLiveSpeakerDiarizerAdapter() {
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

  private func rebuildNotesSummarizer() {
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

    case .ollama:
      let trimmedBase = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let baseURL = URL(string: trimmedBase)
      notesSummarizer = HTTPNotesSummarizer(
        config: HTTPNotesSummarizerConfig(
          provider: .ollama,
          model: effectiveOllamaModelName,
          baseURL: baseURL,
          apiKey: nil
        ),
        diagnostics: diagnostics
      )

    case .openAI:
      guard hasLLMAPIKey else {
        notesSummarizer = nil
        return
      }
      let key = KeychainStore.read(
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      notesSummarizer = HTTPNotesSummarizer(
        config: HTTPNotesSummarizerConfig(
          provider: .openAI,
          model: llmModelName.trimmingCharacters(in: .whitespacesAndNewlines),
          baseURL: nil,
          apiKey: key
        ),
        diagnostics: diagnostics
      )

    case .anthropic:
      guard hasLLMAPIKey else {
        notesSummarizer = nil
        return
      }
      let key = KeychainStore.read(
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      notesSummarizer = HTTPNotesSummarizer(
        config: HTTPNotesSummarizerConfig(
          provider: .anthropic,
          model: llmModelName.trimmingCharacters(in: .whitespacesAndNewlines),
          baseURL: nil,
          apiKey: key
        ),
        diagnostics: diagnostics
      )

    case .openAICompatible:
      let trimmedBase = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let baseURL = URL(string: trimmedBase), !trimmedBase.isEmpty else {
        notesSummarizer = nil
        return
      }
      let key = KeychainStore.read(
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      notesSummarizer = HTTPNotesSummarizer(
        config: HTTPNotesSummarizerConfig(
          provider: .openAICompatible,
          model: llmModelName.trimmingCharacters(in: .whitespacesAndNewlines),
          baseURL: baseURL,
          apiKey: key?.isEmpty == true ? nil : key
        ),
        diagnostics: diagnostics
      )
    }

    maybeUpdateLiveNotes()
  }

  private func rebuildQuestionAnswerer() {
    switch llmProvider {
    case .off, .externalExecutable:
      questionAnswerer = nil

    case .openAI, .anthropic:
      guard hasLLMAPIKey else {
        questionAnswerer = nil
        return
      }
      let key = KeychainStore.read(
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      let modelName = llmModelName.trimmingCharacters(in: .whitespacesAndNewlines)
      questionAnswerer = HTTPRecordingQuestionAnswerer(
        config: HTTPNotesSummarizerConfig(
          provider: llmProvider,
          model: modelName,
          baseURL: nil,
          apiKey: key
        )
      )

    case .openAICompatible:
      let trimmedBase = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let baseURL = URL(string: trimmedBase), !trimmedBase.isEmpty else {
        questionAnswerer = nil
        return
      }
      let key = KeychainStore.read(
        service: "NoteStream",
        account: "llm.\(llmProvider.rawValue)"
      )?.trimmingCharacters(in: .whitespacesAndNewlines)
      questionAnswerer = HTTPRecordingQuestionAnswerer(
        config: HTTPNotesSummarizerConfig(
          provider: .openAICompatible,
          model: llmModelName.trimmingCharacters(in: .whitespacesAndNewlines),
          baseURL: baseURL,
          apiKey: key?.isEmpty == true ? nil : key
        )
      )

    case .ollama:
      let trimmedBase = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let baseURL = URL(string: trimmedBase)
      questionAnswerer = HTTPRecordingQuestionAnswerer(
        config: HTTPNotesSummarizerConfig(
          provider: .ollama,
          model: effectiveOllamaModelName,
          baseURL: baseURL,
          apiKey: nil
        )
      )
    }
  }

  var diagnosticsFolderURL: URL {
    appDiagnosticsURL.deletingLastPathComponent()
  }

  var appDiagnosticsPathText: String {
    appDiagnosticsURL.path
  }

  var sessionDiagnosticsPathText: String? {
    currentSessionDiagnosticsURL?.path
  }

  var diagnosticsSummaryText: String {
    var lines: [String] = []
    lines.append("Model: \(selectedModel)")
    if let status = modelStatus {
      lines.append("ModelStatus: \(status.model) \(String(describing: status.state))")
      if let detail = status.detail { lines.append("ModelDetail: \(detail)") }
    }
    lines.append("UIState: \(String(describing: uiState))")
    lines.append("Frames: \(rollingFrameCount)")
    lines.append("Chunks: \(rollingChunkCount)")
    lines.append(String(format: "RMS: %.4f", lastRMS))
    lines.append("RollingErrors: \(rollingErrorCount)")
    if let rollingLastError { lines.append("RollingLastError: \(rollingLastError)") }
    lines.append("ScreenRecordingPreflight: \(ScreenRecordingPermission.hasPermission())")
    lines.append("AppLog: \(appDiagnosticsURL.path)")
    if let currentSessionDiagnosticsURL {
      lines.append("SessionLog: \(currentSessionDiagnosticsURL.path)")
    }
    lines.append("InMemoryEvents: \(recentDiagnosticsEvents.count) (use Diagnostics → Refresh)")
    return lines.joined(separator: "\n")
  }

  func refreshDiagnosticsEvents() {
    Task { @MainActor in
      self.recentDiagnosticsEvents = await self.memoryDiagnosticsLogger.recentEvents()
    }
  }

  func clearDiagnosticsEvents() {
    Task { @MainActor in
      await self.memoryDiagnosticsLogger.clear()
      self.recentDiagnosticsEvents = []
    }
  }

  func exportDiagnosticsBundle() {
    Task {
      do {
        let bundleURL = try await makeDiagnosticsBundle()
        await MainActor.run {
          NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        }
      } catch {
        await MainActor.run {
          self.errorMessage = "Failed to export diagnostics: \(error.localizedDescription)"
          self.showingError = true
        }
      }
    }
  }

  private func makeDiagnosticsBundle() async throws -> URL {
    let temp =
      FileManager.default.temporaryDirectory
      .appendingPathComponent("NoteStreamDiagnostics-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    if FileManager.default.fileExists(atPath: appDiagnosticsURL.path) {
      try FileManager.default.copyItem(
        at: appDiagnosticsURL,
        to: temp.appendingPathComponent("app.jsonl")
      )
    }

    if let currentSessionDiagnosticsURL,
      FileManager.default.fileExists(atPath: currentSessionDiagnosticsURL.path)
    {
      try FileManager.default.copyItem(
        at: currentSessionDiagnosticsURL,
        to: temp.appendingPathComponent("session-diagnostics.jsonl")
      )
    }

    if let selectedSessionID {
      let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
      let sessionJSON = folder.appendingPathComponent("session.json")

      if FileManager.default.fileExists(atPath: sessionJSON.path) {
        try FileManager.default.copyItem(
          at: sessionJSON,
          to: temp.appendingPathComponent("session.json")
        )
      }
    }

    let environment: [String: String] = [
      "app": "NoteStream",
      "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
      "physicalMemoryGB": "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)",
      "selectedModel": selectedModel,
      "llmProvider": llmProvider.rawValue,
      "llmModelName": llmModelName,
      "speakerDiarizationEnabled": "\(speakerDiarizationEnabled)",
      "notesSummaryEnabled": "\(notesSummaryEnabled)",
    ]

    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try enc.encode(environment)
    try data.write(to: temp.appendingPathComponent("environment.json"), options: .atomic)

    return temp
  }

  private func setUIState(
    _ next: TranscriptionUIState,
    reason: String,
    metadata: [String: String] = [:]
  ) {
    let previous = String(describing: uiState)
    uiState = next
    var merged = metadata
    merged["from"] = previous
    merged["to"] = String(describing: next)
    merged["reason"] = reason

    Task {
      await diagnostics.info(.ui, "ui_state_changed", merged)
    }
  }

  var allSegments: [TranscriptSegment] {
    if case .recording = uiState {
      return liveTranscriptSegments.sorted { $0.startTime < $1.startTime }
    }
    if case .startingRecording = uiState {
      return liveTranscriptSegments.sorted { $0.startTime < $1.startTime }
    }
    return (committedSegments + draftSegments).sorted { $0.startTime < $1.startTime }
  }

  var transcriptMarkdown: String {
    TranscriptMarkdownFormatter.markdown(from: allSegments)
  }

  var transcriptPlainText: String {
    allSegments
      .map { seg in
        let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if let sp = seg.speakerName ?? seg.speakerID, !sp.isEmpty {
          return "\(sp): \(text)"
        }
        return text
      }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  private func mergeRollingUpdate(_ update: TranscriptUpdate) {
    var mergedByKey: [String: TranscriptSegment] = [:]

    for segment in liveTranscriptSegments {
      mergedByKey[segmentKey(segment)] = segment
    }

    for segment in update.committed + update.draft {
      let cleanedText = cleanDisplayText(segment.text)
      guard !cleanedText.isEmpty else { continue }
      var cleaned = segment
      cleaned.text = cleanedText
      let key = segmentKey(cleaned)

      if let existing = mergedByKey[key] {
        if existing.status == .draft && cleaned.status == .committed {
          mergedByKey[key] = cleaned
        }
      } else {
        mergedByKey[key] = cleaned
      }
    }

    liveTranscriptSegments = mergedByKey.values.sorted { $0.startTime < $1.startTime }
    maybeUpdateLiveNotes()
  }

  private func resetNotesStateForNewTranscript() {
    cancelLiveNotesTasks()
    notesMarkdown = ""
    topicTimeline = []
    generatedTitle = nil
    notesStatusText = nil
    liveNotesStatusText = nil
    liveNotesLastUpdatedAt = nil
    lastLiveNotesUpdateAtAudioTime = 0
    lastSummarizedSegmentEndTime = 0
  }

  private func segmentKey(_ segment: TranscriptSegment) -> String {
    let start = Int((segment.startTime * 10).rounded())
    let end = Int((segment.endTime * 10).rounded())
    return "\(start)-\(end)"
  }

  private func cleanDisplayText(_ text: String) -> String {
    TranscriptSanitizer.cleanWhisperText(text)
      .replacingOccurrences(of: "<|startoftranscript|>", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func clear() {
    currentTask?.cancel()
    currentTask = nil
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    startRecordingTask?.cancel()
    startRecordingTask = nil
    if case .startingRecording = uiState {
      Task { await abandonInFlightRecordingStartAfterCancellation() }
    }
    rollingTask?.cancel()
    rollingTask = nil
    selectedFileName = nil
    committedSegments = []
    draftSegments = []
    liveTranscriptSegments = []
    showingError = false
    errorMessage = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    playback.cleanup()

    if let modelStatus,
      modelStatus.model == selectedModel,
      modelStatus.state == .ready
    {
      uiState = .ready(selectedModel)
    } else {
      uiState = .idle
    }
  }

  func openSelectedSessionFolder() {
    guard let id = selectedSessionID else { return }
    Task {
      do {
        let url = try await sessionStore.sessionFolderURL(id: id)
        await MainActor.run {
          _ = NSWorkspace.shared.open(url)
        }
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func openSessionFolder(id: UUID) {
    Task {
      do {
        let url = try await sessionStore.sessionFolderURL(id: id)
        NSWorkspace.shared.open(url)
      } catch {
        errorMessage = String(describing: error)
        showingError = true
      }
    }
  }

  func openSessionTranscript(id: UUID) {
    Task {
      do {
        let folder = try await sessionStore.sessionFolderURL(id: id)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
          throw NSError(
            domain: "NoteStream", code: 41,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Transcript file not found at \(transcriptURL.lastPathComponent)."
            ])
        }
        NSWorkspace.shared.open(transcriptURL)
      } catch {
        errorMessage = String(describing: error)
        showingError = true
      }
    }
  }

  func deleteSession(id: UUID) {
    Task {
      do {
        try await sessionStore.delete(id: id)
        await reloadSessions()
        await MainActor.run {
          if selectedSessionID == id {
            selectedSessionID = nil
          }
        }
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func renameSpeaker(speakerID: String, name: String) {
    let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedName.isEmpty else { return }

    committedSegments = committedSegments.map { segment in
      var updated = segment
      if updated.speakerID == speakerID {
        updated.speakerName = cleanedName
      }
      return updated
    }

    draftSegments = draftSegments.map { segment in
      var updated = segment
      if updated.speakerID == speakerID {
        updated.speakerName = cleanedName
      }
      return updated
    }

    liveTranscriptSegments = liveTranscriptSegments.map { segment in
      var updated = segment
      if updated.speakerID == speakerID {
        updated.speakerName = cleanedName
      }
      return updated
    }

    guard let selectedSessionID else { return }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        session.segments = session.segments.map { segment in
          var updated = segment
          if updated.speakerID == speakerID {
            updated.speakerName = cleanedName
          }
          return updated
        }

        session.metadata.speakerLabels[speakerID] = cleanedName
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func renameSession(id: UUID, title: String) {
    let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTitle.isEmpty else { return }

    Task {
      do {
        var session = try await sessionStore.load(id: id)
        session.title = cleanedTitle
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        await MainActor.run {
          if self.selectedSessionID == id {
            self.selectedFileName = cleanedTitle
            if case .completed = self.uiState {
              self.uiState = .completed(fileName: cleanedTitle)
            }
          }
        }
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func reloadSessions() async {
    do {
      let items = try await sessionStore.list()
      sessions = items
    } catch {
      // Non-fatal; session listing isn't required for transcription to work.
    }
  }

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

  func clearExternalToolPaths() {
    speakerDiarizerCommandPath = ""
    notesSummarizerCommandPath = ""
  }

  func resetExternalToolIntegrations() {
    clearExternalToolPaths()
  }

  func testSpeakerDiarizerOnSelectedSession() {
    guard let selectedSessionID else {
      speakerDiarizationStatusText = "Select a saved session first."
      return
    }

    guard realSpeakerDiarizationIsReady else {
      speakerDiarizationStatusText = realSpeakerDiarizationSetupText
      return
    }

    Task {
      do {
        let session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "Selected session has no saved audio."
          }
          return
        }

        let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
        let audioURL = folder.appendingPathComponent(relativeAudio)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "Audio file not found."
          }
          return
        }

        guard let speakerDiarizer else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "No diarizer configured."
          }
          return
        }

        await MainActor.run {
          self.speakerDiarizationStatusText = "Testing speaker diarizer…"
        }

        let result = try await speakerDiarizer.diarize(
          audioURL: audioURL,
          expectedSpeakerCount: expectedSpeakerCount
        )

        await MainActor.run {
          self.speakerDiarizationStatusText =
            "Diarizer OK: \(result.speakerCount) speakers, \(result.turns.count) turns."
        }
      } catch {
        await MainActor.run {
          self.speakerDiarizationStatusText = "Diarizer test failed: \(String(describing: error))"
        }
      }
    }
  }

  func testNotesSummarizer() {
    guard let notesSummarizer else {
      notesStatusText = "No notes summarizer configured."
      return
    }

    let sampleTranscript = """
      [00:00] Speaker 1: Today we discussed housing supply, land value taxes, and Austin rents.
      [00:10] Speaker 2: Austin allowed more building, and rents dropped despite migration.
      [00:20] Speaker 1: The open question is whether New York can do the same with land constraints.
      """

    notesStatusText = "Testing notes summarizer…"

    let prefs = notesGenerationPreferences
    Task {
      do {
        let result = try await notesSummarizer.summarize(
          NotesSummarizationRequest(
            transcriptMarkdown: sampleTranscript,
            previousNotesMarkdown: nil,
            mode: .final,
            preferences: prefs
          )
        )

        await MainActor.run {
          self.generatedTitle = result.title
          self.notesMarkdown = result.summaryMarkdown
          self.notesStatusText = "Summarizer OK: \(result.title)"
        }
      } catch {
        await MainActor.run {
          self.notesStatusText = "Summarizer test failed: \(String(describing: error))"
        }
      }
    }
  }

  func loadPlaybackForSelectedSession() {
    guard let selectedSessionID else { return }

    Task {
      do {
        let session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.playback.cleanup()
          }
          return
        }

        let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
        let audioURL = folder.appendingPathComponent(relativeAudio)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
          await MainActor.run {
            self.playback.cleanup()
          }
          return
        }

        await MainActor.run {
          self.playback.load(url: audioURL)
        }
      } catch {
        await MainActor.run {
          self.playback.cleanup()
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func seekPlayback(to seconds: TimeInterval) {
    playback.seek(to: seconds)
  }

  func checkForRecoverableRecordings() {
    Task {
      do {
        let files = try await sessionStore.recoverableAudioFiles()
        await MainActor.run {
          self.recoverableAudioFiles = files
          self.showingRecoveryPanel = !files.isEmpty
        }
      } catch {
        // Non-fatal.
      }
    }
  }

  func recoverRecording(at url: URL) {
    startTranscription(for: url)
  }

  private func sanitizedGeneratedTitle(_ raw: String, maxLength: Int = 72) -> String? {
    GeneratedTitleFormatter.sanitize(raw, maxLength: maxLength)
  }

  private func titleAfterAISummary(
    defaultTitle: String,
    currentTitle: String,
    createdAt: Date,
    notesSummary: NotesSummary?
  ) -> String {
    guard autoRenameRecordingsWithAI else { return currentTitle }
    guard notesSummaryEnabled else { return currentTitle }
    guard shouldAutoReplaceTitle(currentTitle, createdAt: createdAt) else { return currentTitle }
    guard let raw = notesSummary?.title else { return currentTitle }
    guard let cleaned = sanitizedGeneratedTitle(raw) else { return currentTitle }

    let lower = cleaned.lowercased()
    if lower == "untitled recording" || lower == "summary" {
      return currentTitle
    }

    return cleaned
  }

  private func shouldAutoReplaceTitle(_ title: String, createdAt: Date) -> Bool {
    let defaultTitle = SessionUIFormatting.recordingSessionTitle(startedAt: createdAt)
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)

    if cleaned.isEmpty { return true }
    if cleaned == defaultTitle { return true }
    if cleaned.hasPrefix("Apr ") || cleaned.hasPrefix("May ") || cleaned.hasPrefix("Jun ") {
      return true
    }
    if cleaned.hasPrefix("Recording ") { return true }

    return false
  }

  private func shouldAutoReplaceImportTitle(_ fileStem: String) -> Bool {
    let s = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return true }
    if s.lowercased() == "untitled" { return true }
    if s.lowercased() == "audio" { return true }
    return false
  }

  private func retainedAudioRelativePathAfterFinalSave() -> String? {
    deleteAudioAfterTranscription ? nil : "audio.caf"
  }

  private func deleteAudioAfterFinalSaveIfNeeded(_ audioURL: URL) async {
    guard deleteAudioAfterTranscription else { return }

    do {
      try FileManager.default.removeItem(at: audioURL)

      await diagnostics.log(
        .init(
          level: .info,
          category: "session",
          message: "audio_deleted_after_transcription",
          metadata: ["audio": audioURL.lastPathComponent]
        ))

      playback.cleanup()
    } catch {
      await diagnostics.log(
        .init(
          level: .warning,
          category: "session",
          message: "audio_delete_failed_after_transcription",
          metadata: [
            "audio": audioURL.lastPathComponent,
            "error": String(describing: error),
          ]
        ))
    }
  }

  func openAINotesSettings() {
    preferredSettingsSectionRaw = "aiNotes"
    showingSettingsPanel = true
  }

  func showOnboardingIfNeeded() {
    guard !onboardingCompleted else { return }
    showingOnboarding = true
  }

  func finishOnboarding() {
    onboardingCompleted = true
    showingOnboarding = false
  }

  func skipOnboarding() {
    onboardingCompleted = true
    showingOnboarding = false
  }

  func runTenSecondTestRecording() {
    startRecording()

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 10_000_000_000)

      if self.liveCaptureShowsRecordingChrome {
        self.stopAndTranscribeRecording()
      }
    }
  }

  func enableAINotes() {
    if llmProvider == .off {
      llmProvider = .ollama
    }

    notesSummaryEnabled = true
    rebuildNotesSummarizer()

    notesStatusText = "AI notes enabled. Generate notes now or finish a recording."
  }

  func askCurrentRecording() {
    let question = askQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return }

    guard let answerer = questionAnswerer else {
      askStatusText = "Choose an LLM provider before asking questions."
      return
    }

    let transcript = TranscriptContextBuilder.markdown(from: allSegments)
    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      askStatusText = "No transcript available."
      return
    }

    isAnsweringQuestion = true
    askStatusText = "Answering…"

    Task {
      do {
        let answer = try await answerer.answer(
          RecordingQuestionRequest(
            transcriptMarkdown: transcript,
            notesMarkdown: notesMarkdown.isEmpty ? nil : notesMarkdown,
            question: question
          )
        )

        await MainActor.run {
          self.askAnswerMarkdown = answer.answerMarkdown
          self.askStatusText = "Answered"
          self.isAnsweringQuestion = false
        }
      } catch {
        await MainActor.run {
          self.askStatusText = "Ask failed: \(String(describing: error))"
          self.isAnsweringQuestion = false
        }
      }
    }
  }

  func regenerateNotesForSelectedSession() {
    guard let selectedSessionID else {
      notesStatusText = "Select a saved session first."
      return
    }

    guard notesSummaryEnabled else {
      notesStatusText = "Notes summary is off."
      return
    }

    guard notesSummarizer != nil else {
      notesStatusText = "Notes summarizer is not configured."
      return
    }

    guard !allSegments.isEmpty else {
      notesStatusText = "No transcript is available to summarize."
      return
    }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        guard !session.segments.isEmpty else {
          await MainActor.run {
            self.notesStatusText = "Selected session has no transcript to summarize."
          }
          return
        }

        await MainActor.run {
          self.notesStatusText = "Regenerating notes…"
        }

        guard
          let notesSummary = await summarizeFinalTranscript(
            segments: session.segments,
            publishNoteFieldsToUI: false
          )
        else {
          await MainActor.run {
            if self.notesStatusText == "Regenerating notes…"
              || self.notesStatusText == "Generating notes…"
            {
              self.notesStatusText = "Notes regeneration did not return a summary."
            }
          }
          return
        }

        session.notesMarkdown = notesSummary.summaryMarkdown

        let renamedTitle = titleAfterAISummary(
          defaultTitle: SessionUIFormatting.recordingSessionTitle(startedAt: session.createdAt),
          currentTitle: session.title,
          createdAt: session.createdAt,
          notesSummary: notesSummary
        )
        session.title = renamedTitle

        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        let titleForUI = session.title

        await MainActor.run {
          self.notesMarkdown = notesSummary.summaryMarkdown
          self.generatedTitle = notesSummary.title
          self.topicTimeline = notesSummary.topicTimeline ?? []
          self.selectedFileName = titleForUI
          self.notesStatusText = "Notes regenerated."
          self.uiState = .completed(fileName: titleForUI)
        }
      } catch {
        await MainActor.run {
          self.notesStatusText = "Notes regeneration failed."
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func updateSegmentText(segmentID: UUID, text: String) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

    committedSegments = committedSegments.map { segment in
      var updated = segment
      if updated.id == segmentID {
        updated.text = cleaned
      }
      return updated
    }

    liveTranscriptSegments = liveTranscriptSegments.map { segment in
      var updated = segment
      if updated.id == segmentID {
        updated.text = cleaned
      }
      return updated
    }

    draftSegments = draftSegments.map { segment in
      var updated = segment
      if updated.id == segmentID {
        updated.text = cleaned
      }
      return updated
    }

    persistCurrentTranscriptEdits()
  }

  func deleteSegment(segmentID: UUID) {
    committedSegments.removeAll { $0.id == segmentID }
    draftSegments.removeAll { $0.id == segmentID }
    liveTranscriptSegments.removeAll { $0.id == segmentID }

    persistCurrentTranscriptEdits()
  }

  func mergeSegmentWithPrevious(segmentID: UUID) {
    var sorted = allSegments.sorted { $0.startTime < $1.startTime }
    guard let index = sorted.firstIndex(where: { $0.id == segmentID }),
      index > 0
    else { return }

    let previous = sorted[index - 1]
    let current = sorted[index]

    let combinedText = [previous.text, current.text]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let merged = TranscriptSegment(
      id: previous.id,
      startTime: previous.startTime,
      endTime: max(previous.endTime, current.endTime),
      text: combinedText,
      status: previous.status,
      confidence: previous.confidence,
      speakerID: previous.speakerID ?? current.speakerID,
      speakerName: previous.speakerName ?? current.speakerName
    )

    sorted[index - 1] = merged
    sorted.remove(at: index)

    committedSegments = sorted.filter { $0.status == .committed }
    draftSegments = sorted.filter { $0.status == .draft }
    liveTranscriptSegments = sorted

    persistCurrentTranscriptEdits()
  }

  func splitSegment(segmentID: UUID, atCharacterOffset offset: Int) {
    let sorted = TranscriptSegmentEditor.split(
      segments: allSegments,
      segmentID: segmentID,
      atCharacterOffset: offset
    )

    committedSegments = sorted.filter { $0.status == .committed }
    draftSegments = sorted.filter { $0.status == .draft }
    liveTranscriptSegments = sorted

    persistCurrentTranscriptEdits()
  }

  private func persistCurrentTranscriptEdits() {
    guard let selectedSessionID else { return }

    let segments = allSegments.sorted { $0.startTime < $1.startTime }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)
        session.segments = segments
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func loadSession(id: UUID) {
    Task {
      do {
        let session = try await sessionStore.load(id: id)
        let labels = session.metadata.speakerLabels
        let mergedSegments = session.segments
          .sorted { $0.startTime < $1.startTime }
          .map { seg -> TranscriptSegment in
            var s = seg
            if let sid = s.speakerID, s.speakerName == nil, let name = labels[sid] {
              s.speakerName = name
            }
            return s
          }
        await MainActor.run {
          selectedSessionID = session.id
          selectedFileName = session.sourceFileName ?? session.title
          committedSegments = mergedSegments
          draftSegments = []
          liveTranscriptSegments = []
          let loadedNotes = session.notesMarkdown ?? ""
          notesMarkdown = loadedNotes
          topicTimeline = []
          askQuestionText = ""
          askAnswerMarkdown = ""
          askStatusText = nil
          generatedTitle = nil
          notesStatusText =
            loadedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : "Saved notes"
          uiState = .completed(fileName: session.title)
        }
        loadPlaybackForSelectedSession()
      } catch {
        await MainActor.run {
          errorMessage = String(describing: error)
          showingError = true
        }
      }
    }
  }

  func diarizeSelectedSession() {
    guard let selectedSessionID else { return }

    #if DEBUG
      let allowDebugOnlyDiarization = isUsingDebugSpeakerLabels && speakerDiarizer != nil
    #else
      let allowDebugOnlyDiarization = false
    #endif

    guard realSpeakerDiarizationIsReady || allowDebugOnlyDiarization else {
      speakerDiarizationStatusText = realSpeakerDiarizationSetupText
      return
    }

    Task {
      do {
        var session = try await sessionStore.load(id: selectedSessionID)

        guard let relativeAudio = session.sourceAudioRelativePath else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "No saved audio file for this session."
          }
          return
        }

        let folder = try await sessionStore.sessionFolderURL(id: selectedSessionID)
        let audioURL = folder.appendingPathComponent(relativeAudio)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
          await MainActor.run {
            self.speakerDiarizationStatusText = "Audio file not found."
          }
          return
        }

        let outcome = await applySpeakerDiarizationIfEnabled(
          to: session.segments,
          audioURL: audioURL
        )

        session.segments = outcome.segments
        session.metadata.speakerDiarizationStatus = outcome.status
        session.metadata.speakerCount = outcome.speakerCount
        session.metadata.speakerLabels = outcome.speakerLabels
        session.metadata.updatedAt = Date()

        try await sessionStore.save(session)
        await reloadSessions()

        let sorted = outcome.segments.sorted { $0.startTime < $1.startTime }
        await MainActor.run {
          self.committedSegments = sorted
          self.draftSegments = []
          self.liveTranscriptSegments = sorted
        }
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func startNew() {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    startRecordingTask?.cancel()
    startRecordingTask = nil
    if case .startingRecording = uiState {
      Task { await abandonInFlightRecordingStartAfterCancellation() }
    }
    rollingTask?.cancel()
    rollingTask = nil
    selectedSessionID = nil
    selectedFileName = nil
    committedSegments = []
    draftSegments = []
    liveTranscriptSegments = []
    audioHealth = .ok
    rollingFrameCount = 0
    rollingChunkCount = 0
    rollingErrorCount = 0
    rollingLastError = nil
    lastRMS = 0
    showingError = false
    errorMessage = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    askQuestionText = ""
    askAnswerMarkdown = ""
    askStatusText = nil
    playback.cleanup()
    prepareSelectedModelIfNeeded(force: false)
  }

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [
      UTType.wav,
      UTType.mp3,
      UTType.mpeg4Audio,
      UTType(filenameExtension: "m4a") ?? .audio,
      UTType(filenameExtension: "flac") ?? .audio,
      .audio,
    ]

    if panel.runModal() == .OK, let url = panel.url {
      startTranscription(for: url)
    }
  }

  func prepareModel() {
    prepareSelectedModelIfNeeded(force: true)
  }

  func prepareSelectedModelIfNeeded(force: Bool = false) {
    if case .recording = uiState { return }
    if case .startingRecording = uiState { return }
    if case .transcribing = uiState { return }
    if case .finalizingTranscript = uiState { return }

    if case .preparingModel(let model) = uiState, model == selectedModel {
      return
    }

    if !force,
      let modelStatus,
      modelStatus.model == selectedModel,
      modelStatus.state == .ready
    {
      return
    }

    uiState = .preparingModel(selectedModel)
    modelPrepareTask = Task {
      await diagnostics.log(
        .init(
          level: .info, category: "model", message: "model_prepare_requested",
          metadata: ["model": selectedModel]))
      await transcriber.prepare(model: selectedModel)
    }
  }

  func retryModel() {
    Task { await modelManager.retry(model: selectedModel) }
  }

  func clearModelCache() {
    Task {
      do {
        try await modelManager.clearModelCache()
        await MainActor.run {
          self.uiState = .idle
        }
      } catch {
        await MainActor.run {
          self.errorMessage = String(describing: error)
          self.showingError = true
        }
      }
    }
  }

  func handleDrop(providers: [NSItemProvider]) -> Bool {
    for provider in providers
    where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        guard let data = item as? Data,
          let url = URL(dataRepresentation: data, relativeTo: nil)
        else { return }
        Task { @MainActor in
          self.startTranscription(for: url)
        }
      }
      return true
    }
    return false
  }

  private func defaultSpeakerLabels(for turns: [SpeakerTurn]) -> [String: String] {
    let ids = Array(Set(turns.map(\.speakerID))).sorted()
    return Dictionary(
      uniqueKeysWithValues: ids.enumerated().map { index, id in
        (id, "Speaker \(index + 1)")
      })
  }

  private func speakerLabelMap(from segments: [TranscriptSegment]) -> [String: String] {
    var labels: [String: String] = [:]
    for segment in segments {
      if let id = segment.speakerID, let name = segment.speakerName {
        labels[id] = name
      }
    }
    return labels
  }

  private func applySpeakerDiarizationIfEnabled(
    to segments: [TranscriptSegment],
    audioURL: URL
  ) async -> (
    segments: [TranscriptSegment], status: String?, speakerCount: Int?,
    speakerLabels: [String: String]
  ) {
    guard speakerDiarizationEnabled else {
      return (segments, nil, nil, [:])
    }

    guard let speakerDiarizer else {
      speakerDiarizationStatusText = realSpeakerDiarizationSetupText
      return (segments, "not_configured", nil, [:])
    }

    speakerDiarizationStatusText = "Detecting speakers…"

    do {
      let result = try await speakerDiarizer.diarize(
        audioURL: audioURL,
        expectedSpeakerCount: expectedSpeakerCount
      )

      let labels = defaultSpeakerLabels(for: result.turns)

      let diarized = SpeakerTurnAligner.assignSpeakers(
        segments: segments,
        turns: result.turns,
        speakerLabels: labels
      )

      let speakerLabels = speakerLabelMap(from: diarized)

      speakerDiarizationStatusText =
        "Detected \(result.speakerCount) speaker\(result.speakerCount == 1 ? "" : "s")"

      return (diarized, "speaker_diarization_ok", result.speakerCount, speakerLabels)
    } catch {
      let message = String(describing: error)

      speakerDiarizationStatusText = "Speaker detection failed"
      rollingLastError = message

      return (segments, "speaker_diarization_failed", nil, [:])
    }
  }

  private func startLiveSpeakerDiarizationIfNeededAsync() async {
    guard liveSpeakerDiarizationEnabled else {
      isLiveSpeakerDiarizationActive = false
      liveSpeakerStatusText = nil
      return
    }
    guard speakerDiarizationEnabled else {
      isLiveSpeakerDiarizationActive = false
      liveSpeakerStatusText = nil
      return
    }
    guard let diarizer = liveSpeakerDiarizer else {
      isLiveSpeakerDiarizationActive = false
      liveSpeakerStatusText = "Live speaker labels require a real diarizer tool."
      return
    }

    liveSpeakerTurns = []
    isLiveSpeakerDiarizationActive = true
    liveSpeakerStatusText = "Live speaker labeling active"

    do {
      try await diarizer.start(expectedSpeakerCount: expectedSpeakerCount)
    } catch {
      liveSpeakerStatusText = "Live speaker setup failed."
      isLiveSpeakerDiarizationActive = false
    }
  }

  private func stopLiveSpeakerDiarizationAsync() async {
    liveDiarizationTask?.cancel()
    liveDiarizationTask = nil
    isLiveSpeakerDiarizationActive = false

    if let diarizer = liveSpeakerDiarizer {
      _ = try? await diarizer.finish()
      await diarizer.reset()
    }

    liveSpeakerTurns = []
    liveSpeakerStatusText = nil
  }

  private func stopLiveSpeakerDiarizationSync() {
    liveDiarizationTask?.cancel()
    liveDiarizationTask = nil
    isLiveSpeakerDiarizationActive = false
    liveSpeakerTurns = []
    liveSpeakerStatusText = nil
    let diarizer = liveSpeakerDiarizer
    Task {
      await diarizer?.reset()
    }
  }

  private func scheduleLiveDiarizationFrame(_ frame: AudioFrame) {
    guard liveSpeakerDiarizationEnabled,
      speakerDiarizationEnabled,
      isLiveSpeakerDiarizationActive,
      let diarizer = liveSpeakerDiarizer
    else { return }

    Task.detached(priority: .utility) { [weak self] in
      do {
        guard let update = try await diarizer.ingest(frame: frame) else { return }
        await MainActor.run { [weak self] in
          self?.applyLiveSpeakerDiarizationUpdate(update)
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.liveSpeakerStatusText =
            "Live speaker update failed: \(error.localizedDescription)"
        }
      }
    }
  }

  private func applyLiveSpeakerDiarizationUpdate(_ update: LiveSpeakerDiarizationUpdate) {
    mergeLiveSpeakerTurns(update.turns)
    applyLiveSpeakerLabelsToRecentSegments(windowStart: update.windowStartTime)
  }

  private func mergeLiveSpeakerTurns(_ newTurns: [SpeakerTurn]) {
    guard !newTurns.isEmpty else { return }

    let minStart = newTurns.map(\.startTime).min() ?? 0
    let maxEnd = newTurns.map(\.endTime).max() ?? minStart

    liveSpeakerTurns.removeAll { turn in
      !(turn.endTime <= minStart || turn.startTime >= maxEnd)
    }

    liveSpeakerTurns.append(contentsOf: newTurns)
    liveSpeakerTurns.sort { $0.startTime < $1.startTime }
  }

  private func applyLiveSpeakerLabelsToRecentSegments(windowStart: TimeInterval) {
    guard !liveSpeakerTurns.isEmpty else { return }

    let labels = defaultSpeakerLabels(for: liveSpeakerTurns)

    let recentSegments =
      liveTranscriptSegments
      .filter { $0.endTime >= windowStart }

    let recentIDs = Set(recentSegments.map(\.id))

    let relabeledRecent = SpeakerTurnAligner.assignSpeakers(
      segments: recentSegments,
      turns: liveSpeakerTurns,
      speakerLabels: labels
    )

    let relabeledByID = Dictionary(uniqueKeysWithValues: relabeledRecent.map { ($0.id, $0) })

    liveTranscriptSegments = liveTranscriptSegments.map { segment in
      if recentIDs.contains(segment.id), let updated = relabeledByID[segment.id] {
        return updated
      }
      return segment
    }

    committedSegments = committedSegments.map { segment in
      if recentIDs.contains(segment.id), let updated = relabeledByID[segment.id] {
        return updated
      }
      return segment
    }

    draftSegments = draftSegments.map { segment in
      if recentIDs.contains(segment.id), let updated = relabeledByID[segment.id] {
        return updated
      }
      return segment
    }
  }

  private enum OllamaNotesSummarizationPolicy {
    /// If the committed transcript spans longer than this, run staged chunk summaries (local models).
    static let mergeChunkingMinSpanSeconds: TimeInterval = 600
    /// Max wall-clock span per chunk (~8 minutes).
    static let chunkMaxSpanSeconds: TimeInterval = 480
  }

  private func transcriptTimeSpanSeconds(_ segments: [TranscriptSegment]) -> TimeInterval {
    let sorted = segments.filter { $0.status == .committed }.sorted { $0.startTime < $1.startTime }
    guard let first = sorted.first, let last = sorted.last else { return 0 }
    return max(0, last.endTime - first.startTime)
  }

  private func shouldUseOllamaChunkedSummarization(segments: [TranscriptSegment]) -> Bool {
    guard llmProvider == .ollama else { return false }
    return transcriptTimeSpanSeconds(segments)
      > OllamaNotesSummarizationPolicy.mergeChunkingMinSpanSeconds
  }

  /// Long Ollama runs: summarize time-chunks, then one merge pass for a single `NotesSummary`.
  private func summarizeWithOllamaChunking(
    segments: [TranscriptSegment],
    notesSummarizer: any NotesSummarizing,
    publishNoteFieldsToUI: Bool
  ) async throws -> NotesSummary {
    let sorted = segments.filter { $0.status == .committed }.sorted { $0.startTime < $1.startTime }
    let chunks = TranscriptTimeChunker.chunkSegments(
      sorted,
      maxSpanSeconds: OllamaNotesSummarizationPolicy.chunkMaxSpanSeconds
    )
    guard chunks.count > 1 else {
      let md = TranscriptContextBuilder.markdown(from: segments)
      return try await notesSummarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: md,
          previousNotesMarkdown: nil,
          mode: .final,
          preferences: notesGenerationPreferences
        )
      )
    }

    var chunkDigests: [String] = []
    for (index, chunk) in chunks.enumerated() {
      if publishNoteFieldsToUI {
        notesStatusText = "Generating notes (part \(index + 1)/\(chunks.count))…"
      }

      let md = TranscriptContextBuilder.markdown(from: chunk)
      guard !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

      let partial = try await notesSummarizer.summarize(
        NotesSummarizationRequest(
          transcriptMarkdown: md,
          previousNotesMarkdown: nil,
          mode: .final,
          preferences: notesGenerationPreferences
        )
      )

      let partTitle = partial.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let partBody = partial.summaryMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
      chunkDigests.append(
        "### Part \(index + 1)\n**\(partTitle)**\n\n\(partBody)"
      )
    }

    let combined = chunkDigests.joined(separator: "\n\n")
    guard !combined.isEmpty else {
      throw NSError(
        domain: "NoteStream", code: 88,
        userInfo: [NSLocalizedDescriptionKey: "Chunked summarization produced no text."]
      )
    }

    if publishNoteFieldsToUI {
      notesStatusText = "Merging partial summaries…"
    }

    let mergePrompt = """
      You are given partial notes from consecutive time segments of one recording. Merge them into ONE JSON object matching the usual notes schema (title, summaryMarkdown, keyPoints, actionItems, openQuestions, topicTimeline). Remove duplicates, keep chronology where helpful, and do not invent facts. topicTimeline should be 5 to 12 items with startTime in seconds, title, and optional summary.

      Partial summaries:
      \(combined)
      """

    return try await notesSummarizer.summarize(
      NotesSummarizationRequest(
        transcriptMarkdown: mergePrompt,
        previousNotesMarkdown: nil,
        mode: .final,
        preferences: notesGenerationPreferences
      )
    )
  }

  private func summarizeFinalTranscript(
    segments: [TranscriptSegment],
    publishNoteFieldsToUI: Bool = true
  ) async -> NotesSummary? {
    guard notesSummaryEnabled else {
      if publishNoteFieldsToUI {
        notesStatusText = nil
      }
      return nil
    }

    guard let notesSummarizer else {
      if publishNoteFieldsToUI {
        notesStatusText = "Notes unavailable. Set a notes summarizer command path."
      }
      return nil
    }

    let transcript = TranscriptContextBuilder.markdown(from: segments)
    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    if publishNoteFieldsToUI {
      notesStatusText = "Generating notes…"
    }

    do {
      let result: NotesSummary
      if shouldUseOllamaChunkedSummarization(segments: segments) {
        result = try await summarizeWithOllamaChunking(
          segments: segments,
          notesSummarizer: notesSummarizer,
          publishNoteFieldsToUI: publishNoteFieldsToUI
        )
      } else {
        result = try await notesSummarizer.summarize(
          NotesSummarizationRequest(
            transcriptMarkdown: transcript,
            previousNotesMarkdown: nil,
            mode: .final,
            preferences: notesGenerationPreferences
          )
        )
      }

      if publishNoteFieldsToUI {
        generatedTitle = result.title
        notesMarkdown = result.summaryMarkdown
        notesStatusText = "Notes generated"
        topicTimeline = result.topicTimeline ?? []
      }

      return result
    } catch {
      if publishNoteFieldsToUI {
        notesStatusText = "Notes generation failed"
      }
      rollingLastError = String(describing: error)
      return nil
    }
  }

  private func cancelLiveNotesTasks() {
    notesTask?.cancel()
    notesTask = nil
    isGeneratingLiveNotes = false
  }

  /// Called frequently from the rolling transcript path; interval and character gates limit work.
  func maybeUpdateLiveNotes() {
    updateLiveNotes(force: false)
  }

  func refreshLiveNotesNow() {
    updateLiveNotes(force: true)
  }

  private func updateLiveNotes(force: Bool) {
    guard isRecording else { return }
    guard liveNotesEnabled else { return }
    guard notesSummaryEnabled else { return }
    guard notesTask == nil else { return }
    guard let summarizer = notesSummarizer else { return }

    let committed =
      liveTranscriptSegments
      .filter { $0.status == .committed }
      .sorted { $0.startTime < $1.startTime }

    guard let latestEnd = committed.map(\.endTime).max() else {
      liveNotesStatusText = "Waiting for transcript…"
      return
    }

    if shouldUseOllamaChunkedSummarization(segments: committed), !force {
      liveNotesStatusText =
        "Live notes paused; transcript is long. Final notes run after Stop & Transcribe."
      return
    }

    if !force {
      let intervalSeconds = TimeInterval(liveNotesIntervalMinutes * 60)
      guard latestEnd - lastLiveNotesUpdateAtAudioTime >= intervalSeconds else {
        return
      }
    }

    let startAfter: TimeInterval = force ? 0 : lastSummarizedSegmentEndTime
    let newText = TranscriptContextBuilder.markdown(
      from: committed,
      startingAfter: startAfter
    )

    guard newText.count >= liveNotesMinimumCharacters || force else {
      liveNotesStatusText = "Waiting for \(liveNotesMinimumCharacters)+ new transcript characters…"
      return
    }

    let previousNotes = notesMarkdown
    isGeneratingLiveNotes = true
    liveNotesStatusText = "Updating live notes…"

    let prefs = notesGenerationPreferences
    notesTask = Task { [weak self, summarizer, newText, previousNotes, prefs, latestEnd] in
      guard let self else { return }
      do {
        let result = try await summarizer.summarize(
          NotesSummarizationRequest(
            transcriptMarkdown: newText,
            previousNotesMarkdown: previousNotes.isEmpty ? nil : previousNotes,
            mode: .liveUpdate,
            preferences: prefs
          )
        )

        await MainActor.run {
          self.notesMarkdown = result.summaryMarkdown
          self.topicTimeline = result.topicTimeline ?? self.topicTimeline
          self.liveNotesStatusText = "Live notes updated"
          self.liveNotesLastUpdatedAt = Date()
          self.lastSummarizedSegmentEndTime = latestEnd
          self.lastLiveNotesUpdateAtAudioTime = latestEnd
          self.isGeneratingLiveNotes = false
          self.notesTask = nil
        }
      } catch {
        await MainActor.run {
          self.liveNotesStatusText = "Live notes failed"
          self.rollingLastError = String(describing: error)
          self.isGeneratingLiveNotes = false
          self.notesTask = nil
        }
      }
    }
  }

  private func startTranscription(for url: URL) {
    // Prevent concurrent transcriptions.
    if case .transcribing = uiState { return }
    if case .recording = uiState { return }
    if case .startingRecording = uiState { return }

    selectedFileName = url.lastPathComponent
    committedSegments = []
    draftSegments = []
    resetNotesStateForNewTranscript()
    askQuestionText = ""
    askAnswerMarkdown = ""
    askStatusText = nil
    showingError = false
    errorMessage = nil
    uiState = .transcribing(fileName: url.lastPathComponent)

    currentTask = Task {
      do {
        // Always prepare; transcriber will block until model is ready.
        await transcriber.prepare(model: selectedModel)

        let incoming = try await transcriber.transcribeFile(
          at: url,
          model: selectedModel,
          onProgress: { [weak self] progress in
            guard let self else { return }
            let snippet = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
              Task { @MainActor in
                // Keep UI stable: we don't stream transcript text in Phase 1,
                // but we can show an informative progress snippet.
                self.uiState = .transcribing(fileName: url.lastPathComponent)
              }
            }
          }
        )

        let coordinator = TranscriptCoordinator()
        let update = await coordinator.ingestRollingSegments(
          chunkStart: 0,
          chunkEnd: TimeInterval(incoming.last?.endTime ?? 0),
          segments: incoming,
          currentAudioTime: TimeInterval(incoming.last?.endTime ?? 0),
          boundary: .recordingStopped
        )

        let cleaned = TranscriptSanitizer.sanitize(update.committed)

        let speakerOutcome = await applySpeakerDiarizationIfEnabled(
          to: cleaned,
          audioURL: url
        )
        let finalTranscriptSegments = speakerOutcome.segments

        let notesSummary = await summarizeFinalTranscript(segments: finalTranscriptSegments)

        let defaultFileTitle = url.deletingPathExtension().lastPathComponent
        let finalTitle: String
        if autoRenameRecordingsWithAI,
          notesSummaryEnabled,
          shouldAutoReplaceImportTitle(defaultFileTitle),
          let cleaned = GeneratedTitleFormatter.sanitize(notesSummary?.title ?? "")
        {
          finalTitle = cleaned
        } else {
          finalTitle = defaultFileTitle
        }

        committedSegments = finalTranscriptSegments
        draftSegments = update.draft
        liveTranscriptSegments = finalTranscriptSegments
        notesMarkdown = notesSummary?.summaryMarkdown ?? ""
        generatedTitle = notesSummary?.title
        topicTimeline = notesSummary?.topicTimeline ?? []
        selectedFileName = finalTitle
        uiState = .completed(fileName: finalTitle)

        let session = LectureSession(
          title: finalTitle,
          sourceFileName: url.lastPathComponent,
          model: selectedModel,
          segments: finalTranscriptSegments,
          notesMarkdown: notesSummary?.summaryMarkdown,
          metadata: SessionMetadata(
            transcriptionStatus: "final_ok",
            speakerDiarizationStatus: speakerOutcome.status,
            speakerCount: speakerOutcome.speakerCount,
            speakerLabels: speakerOutcome.speakerLabels
          )
        )
        try await sessionStore.save(session)
        await reloadSessions()
      } catch is CancellationError {
        uiState = .idle
      } catch {
        let msg = String(describing: error)
        uiState = .failed(message: msg)
        errorMessage = msg
        showingError = true
      }
    }
  }

  private func startRecordingStartupWatchdog(startedAt: Date) {
    recordingStartupWatchdogTask?.cancel()

    recordingStartupWatchdogTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 9_000_000_000)

      guard !Task.isCancelled else { return }

      guard case .startingRecording(let currentStartedAt) = self.uiState,
        currentStartedAt == startedAt
      else { return }

      self.startRecordingTask?.cancel()
      self.startRecordingTask = nil
      self.errorMessage =
        "Timed out starting system audio capture. Capture state was reset. Try again."
      self.showingError = true
      let failMsg = self.errorMessage ?? "Recording startup timed out."
      self.setUIState(.failed(message: failMsg), reason: "recording_start_timed_out")
      self.stopRecordingTimer()

      await self.diagnostics.error(.recorder, "recording_start_timed_out", nil, [:])

      _ = try? await self.recorder.stopRecording()

      self.recordingStartupWatchdogTask = nil
    }
  }

  func startRecording() {
    if isBusy { return }

    let optimisticStartedAt = Date()
    setUIState(
      .startingRecording(startedAt: optimisticStartedAt), reason: "recording_start_requested")
    startRecordingTimer()
    startRecordingStartupWatchdog(startedAt: optimisticStartedAt)

    showingError = false
    errorMessage = nil
    rollingFrameCount = 0
    rollingChunkCount = 0
    rollingErrorCount = 0
    rollingLastError = nil
    lastRMS = 0
    audioHealth = .ok
    liveTranscriptSegments = []
    committedSegments = []
    draftSegments = []
    selectedSessionID = nil
    selectedFileName = nil
    resetNotesStateForNewTranscript()
    stopLiveSpeakerDiarizationSync()
    playback.cleanup()

    startRecordingTask?.cancel()

    startRecordingTask = Task {
      do {
        if !ScreenRecordingPermission.hasPermission() {
          let granted = await ScreenRecordingPermission.request()
          if Task.isCancelled { return }
          if !granted {
            showingPermissionPanel = true
            recordingStartupWatchdogTask?.cancel()
            recordingStartupWatchdogTask = nil
            setUIState(.ready(selectedModel), reason: "permission_denied")
            stopRecordingTimer()
            return
          }
        }

        let sessionId = UUID()
        let folder = try await sessionStore.sessionFolderURL(id: sessionId)
        let audioURL = folder.appendingPathComponent("audio.caf")
        currentSessionDiagnosticsURL = folder.appendingPathComponent("diagnostics.jsonl")

        let rec = try await Task.detached(priority: .userInitiated) { [recorder] in
          try await recorder.startRecording(outputURL: audioURL)
        }.value

        if Task.isCancelled {
          activeRecording = RecordingSession(
            id: sessionId,
            startedAt: rec.startedAt,
            outputURL: audioURL
          )
          await abandonInFlightRecordingStartAfterCancellation()
          return
        }

        activeRecording = RecordingSession(
          id: sessionId,
          startedAt: rec.startedAt,
          outputURL: audioURL
        )

        setUIState(
          .recording(startedAt: rec.startedAt),
          reason: "recording_started",
          metadata: ["sessionID": sessionId.uuidString]
        )
        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = nil
        startRecordingTimer()
        await startLiveSpeakerDiarizationIfNeededAsync()
        maybeUpdateLiveNotes()

        let stream = await recorder.audioFrames()
        let pipeline = RollingTranscriptionPipeline(
          transcriber: transcriber,
          diagnostics: diagnostics
        )

        rollingTask?.cancel()
        rollingTask = Task {
          let meter = RMSMeter()

          let frames = AsyncThrowingStream<AudioFrame, Error> { continuation in
            let t = Task {
              for await frame in stream {
                await MainActor.run {
                  self.rollingFrameCount += 1
                  self.lastRMS = meter.rms(of: frame.samples)
                  self.scheduleLiveDiarizationFrame(frame)
                }
                continuation.yield(frame)
              }
              continuation.finish()
            }

            continuation.onTermination = { _ in
              t.cancel()
            }
          }

          let updates = await pipeline.run(
            frames: frames,
            model: selectedModel
          )

          do {
            for try await update in updates {
              await MainActor.run {
                self.rollingChunkCount += 1
                self.audioHealth = update.audioHealth
                self.mergeRollingUpdate(update)
                self.committedSegments = self.liveTranscriptSegments.filter {
                  $0.status == .committed
                }
                self.draftSegments = self.liveTranscriptSegments.filter { $0.status == .draft }
                self.maybeUpdateLiveNotes()
              }
            }
          } catch {
            await MainActor.run {
              self.rollingErrorCount += 1
              self.rollingLastError = String(describing: error)
            }
          }
        }
      } catch {
        await recoverFromRecordingStartFailure(error)
      }
    }
  }

  private func recoverFromRecordingStartFailure(_ error: Error) async {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    rollingTask?.cancel()
    rollingTask = nil
    cancelLiveNotesTasks()
    await stopLiveSpeakerDiarizationAsync()
    activeRecording = nil
    let sessionLogPath = currentSessionDiagnosticsURL?.path
    currentSessionDiagnosticsURL = nil
    stopRecordingTimer()

    _ = try? await recorder.stopRecording()

    let ns = error as NSError
    var hint = ""
    if ns.domain == "NoteStream", ns.code == 13 {
      hint =
        "SCK startup exceeded the in-app timeout. Search diagnostics for recorder / SCK messages."
    }
    await diagnostics.error(
      .transcription,
      "recording_start_failed_ui",
      error,
      [
        "screenRecordingPermission": "\(ScreenRecordingPermission.hasPermission())",
        "sessionLogPath": sessionLogPath ?? "",
        "hint": hint,
      ]
    )

    let msg: String

    if ns.domain == "NoteStream", ns.code == 10 {
      msg =
        "Recording was already in progress, but the app state was out of sync. Capture has been reset. Try recording again."
    } else {
      msg = String(describing: error)
    }

    setUIState(.failed(message: msg), reason: "recording_start_failed")
    errorMessage = msg
    showingError = true
  }

  private func abandonInFlightRecordingStartAfterCancellation() async {
    recordingStartupWatchdogTask?.cancel()
    recordingStartupWatchdogTask = nil
    rollingTask?.cancel()
    rollingTask = nil
    cancelLiveNotesTasks()
    await stopLiveSpeakerDiarizationAsync()
    currentSessionDiagnosticsURL = nil
    stopRecordingTimer()

    _ = try? await recorder.stopRecording()

    activeRecording = nil

    setUIState(.ready(selectedModel), reason: "recording_start_abandoned")
  }

  func stopAndTranscribeRecording() {
    if case .startingRecording = uiState {
      startRecordingTask?.cancel()
      startRecordingTask = nil
      rollingTask?.cancel()
      rollingTask = nil
      Task {
        await abandonInFlightRecordingStartAfterCancellation()
      }
      return
    }

    guard case .recording = uiState else { return }

    // UI can be ".recording" while `activeRecording` is nil (failed/partial start). Let the user recover.
    guard let activeRecording else {
      Task {
        await diagnostics.log(
          .init(
            level: .warning, category: "transcription", message: "stop_with_no_active_recording",
            metadata: ["uiState": String(describing: uiState)]))
        await MainActor.run {
          self.uiState = .ready(self.selectedModel)
          self.stopRecordingTimer()
        }
        // Best effort: if SCK is wedged, try to clear recorder state.
        _ = try? await recorder.stopRecording()
      }
      return
    }

    cancelLiveNotesTasks()
    liveNotesStatusText = nil
    liveNotesLastUpdatedAt = nil
    lastLiveNotesUpdateAtAudioTime = 0
    lastSummarizedSegmentEndTime = 0

    let capRolling =
      liveTranscriptSegments
      .sorted { $0.startTime < $1.startTime }
      .map { segment in
        var s = segment
        s.status = .committed
        s.text = cleanDisplayText(s.text)
        return s
      }

    let rec = activeRecording
    let model = selectedModel
    let transcriber = self.transcriber
    let sessionStore = self.sessionStore
    let diag = self.diagnostics

    rollingTask?.cancel()
    rollingTask = nil
    notesTask?.cancel()
    notesTask = nil
    isGeneratingLiveNotes = false
    draftSegments = []
    currentTask?.cancel()

    setUIState(
      .finalizingTranscript(fileName: rec.outputURL.lastPathComponent),
      reason: "recording_stop_requested",
      metadata: ["sessionID": rec.id.uuidString]
    )

    currentTask = Task {
      do {
        cancelLiveNotesTasks()
        await self.stopLiveSpeakerDiarizationAsync()

        await diag.log(
          .init(
            level: .info,
            category: "transcription",
            message: "rolling_snapshot_captured",
            metadata: ["segments": "\(capRolling.count)"]
          ))
        await diag.log(
          .init(
            level: .info, category: "transcription", message: "final_transcription_started",
            metadata: ["model": model]))
        await diag.log(
          .init(
            level: .info, category: "transcription", message: "stop_and_transcribe_begin",
            metadata: [
              "session": rec.id.uuidString,
              "audio": rec.outputURL.lastPathComponent,
            ]))

        let audioURL: URL
        do {
          // Never block the main actor on SCK / file IO / Whisper.
          audioURL = try await Task.detached(priority: .userInitiated) { [recorder] in
            try await recorder.stopRecording()
          }.value
        } catch {
          await diag.log(
            .init(
              level: .error, category: "transcription", message: "recorder_stop_failed",
              metadata: ["error": String(describing: error)]))
          throw error
        }

        do {
          try self.validateAudioFile(audioURL)
        } catch {
          // Still save a session stub so the user can see failure + has the folder.
          let failedSession = LectureSession(
            id: rec.id,
            title: SessionUIFormatting.recordingSessionTitle(startedAt: rec.startedAt),
            createdAt: rec.startedAt,
            sourceFileName: nil,
            sourceAudioRelativePath: "audio.caf",
            model: model,
            segments: [],
            metadata: SessionMetadata(
              createdAt: rec.startedAt,
              updatedAt: Date(),
              transcriptionStatus: "failed",
              errorMessage: String(describing: error),
              speakerDiarizationStatus: nil,
              speakerCount: nil,
              speakerLabels: [:]
            )
          )
          try? await sessionStore.save(failedSession)
          await reloadSessions()
          throw error
        }

        // Run a full-file pass for correctness. Rolling transcript is preview-only.
        await Task.detached(priority: .userInitiated) { [transcriber, model] in
          await transcriber.prepare(model: model)
        }.value

        // swiftlint:disable closure_parameter_position
        let finalSegments: [TranscriptSegment] = try await Task.detached(priority: .userInitiated) {
          [transcriber, model, audioURL] in
          try await transcriber.transcribeFile(
            at: audioURL,
            model: model,
            onProgress: { _ in }
          )
        }.value
        // swiftlint:enable closure_parameter_position

        let coordinator = TranscriptCoordinator()
        let update = await coordinator.ingestRollingSegments(
          chunkStart: 0,
          chunkEnd: TimeInterval(finalSegments.last?.endTime ?? 0),
          segments: finalSegments,
          currentAudioTime: TimeInterval(finalSegments.last?.endTime ?? 0),
          boundary: .recordingStopped
        )

        let cleaned = TranscriptSanitizer.sanitize(update.committed)

        let speakerOutcome = await applySpeakerDiarizationIfEnabled(
          to: cleaned,
          audioURL: audioURL
        )
        let finalTranscriptSegments = speakerOutcome.segments

        let notesSummary = await summarizeFinalTranscript(segments: finalTranscriptSegments)

        let defaultRecordingTitle = SessionUIFormatting.recordingSessionTitle(
          startedAt: rec.startedAt)
        let finalTitle = titleAfterAISummary(
          defaultTitle: defaultRecordingTitle,
          currentTitle: defaultRecordingTitle,
          createdAt: rec.startedAt,
          notesSummary: notesSummary
        )

        let status = finalTranscriptSegments.isEmpty ? "empty_final_transcript" : "final_ok"
        let statusMsg =
          finalTranscriptSegments.isEmpty ? "Final transcription produced no segments." : nil

        let retainedAudioPath = retainedAudioRelativePathAfterFinalSave()

        let session = LectureSession(
          id: rec.id,
          title: finalTitle,
          createdAt: rec.startedAt,
          sourceFileName: nil,
          sourceAudioRelativePath: retainedAudioPath,
          model: model,
          segments: finalTranscriptSegments,
          notesMarkdown: notesSummary?.summaryMarkdown,
          metadata: SessionMetadata(
            createdAt: rec.startedAt,
            updatedAt: Date(),
            transcriptionStatus: status,
            errorMessage: statusMsg,
            speakerDiarizationStatus: speakerOutcome.status,
            speakerCount: speakerOutcome.speakerCount,
            speakerLabels: speakerOutcome.speakerLabels
          )
        )
        try await sessionStore.save(session)
        await deleteAudioAfterFinalSaveIfNeeded(audioURL)

        await diag.log(
          .init(
            level: .info,
            category: "session",
            message: "session_saved",
            metadata: [
              "id": session.id.uuidString,
              "segments": "\(finalTranscriptSegments.count)",
              "status": session.metadata.transcriptionStatus ?? "",
            ]
          ))
        await reloadSessions()

        await MainActor.run {
          self.committedSegments = finalTranscriptSegments
          self.draftSegments = []
          self.liveTranscriptSegments = finalTranscriptSegments
          self.selectedSessionID = session.id
          self.selectedFileName = session.title
          self.notesMarkdown = notesSummary?.summaryMarkdown ?? ""
          self.generatedTitle = notesSummary?.title
          self.topicTimeline = notesSummary?.topicTimeline ?? []
          self.uiState = .completed(fileName: session.title)

          if retainedAudioPath == nil {
            self.playback.cleanup()
          }
        }

        self.activeRecording = nil
        self.currentSessionDiagnosticsURL = nil
        self.stopRecordingTimer()
      } catch {
        let msg = String(describing: error)
        await diag.log(
          .init(
            level: .error,
            category: "transcription",
            message: "final_transcription_failed",
            metadata: ["error": msg]
          ))

        let fallback = TranscriptSanitizer.sanitize(capRolling)

        let status = fallback.isEmpty ? "failed" : "rolling_only"
        let userMessage =
          fallback.isEmpty
          ? msg : "Final transcription failed. Saved the rolling transcript instead. Error: \(msg)"

        let failedSession = LectureSession(
          id: rec.id,
          title: SessionUIFormatting.recordingSessionTitle(startedAt: rec.startedAt),
          createdAt: rec.startedAt,
          sourceFileName: nil,
          sourceAudioRelativePath: "audio.caf",
          model: model,
          segments: fallback,
          metadata: SessionMetadata(
            createdAt: rec.startedAt,
            updatedAt: Date(),
            transcriptionStatus: status,
            errorMessage: userMessage,
            speakerDiarizationStatus: nil,
            speakerCount: nil,
            speakerLabels: [:]
          )
        )

        try? await sessionStore.save(failedSession)
        await reloadSessions()

        await MainActor.run {
          self.committedSegments = fallback
          self.draftSegments = []
          self.liveTranscriptSegments = fallback
          self.selectedSessionID = failedSession.id
          self.selectedFileName = failedSession.title

          if fallback.isEmpty {
            self.uiState = .failed(message: userMessage)
            self.errorMessage = userMessage
            self.showingError = true
          } else {
            self.uiState = .completed(fileName: failedSession.title)
          }
        }

        self.activeRecording = nil
        self.currentSessionDiagnosticsURL = nil
        self.stopRecordingTimer()
      }
    }
  }

  var canTranscribeNow: Bool {
    switch uiState {
    case .ready, .completed:
      return true
    case .idle, .preparingModel, .startingRecording, .recording, .transcribing,
      .finalizingTranscript, .failed:
      return false
    }
  }

  var isBusy: Bool {
    if case .preparingModel = uiState { return true }
    if case .startingRecording = uiState { return true }
    if case .recording = uiState { return true }
    if case .transcribing = uiState { return true }
    if case .finalizingTranscript = uiState { return true }
    return false
  }

  var statusText: String? {
    // Always prioritize live capture/transcription UI state. Otherwise "model ready" overrides
    // recording/finalizing and makes the app look idle while work is in progress.
    switch uiState {
    case .idle:
      break
    case .preparingModel:
      return "Preparing speech model…"
    case .ready:
      break
    case .startingRecording:
      return "Starting system audio capture…"
    case .recording:
      return "Recording… \(recordingElapsedText)"
    case .transcribing(let fileName):
      return "Transcribing \(fileName)…"
    case .finalizingTranscript(let fileName):
      return "Finalizing transcript… \(fileName)"
    case .completed(let fileName):
      return "Completed: \(fileName)"
    case .failed(let message):
      return "Failed: \(message)"
    }

    if let status = modelStatus, status.model == selectedModel {
      switch status.state {
      case .idle:
        break
      case .downloading(let fraction):
        if let fraction {
          return "Installing speech model… \(Int((fraction * 100).rounded()))%"
        }
        return "Installing speech model…"
      case .loading:
        return "Loading speech model into memory…"
      case .ready:
        return "Speech model ready"
      case .failed(let message):
        return "Speech model failed: \(message)"
      }
    }

    switch uiState {
    case .idle:
      return "Speech model not installed"
    case .ready:
      return "Speech model ready"
    default:
      return nil
    }
  }

  private var recordingElapsedText: String {
    let startedAt: Date?
    switch uiState {
    case .recording(let t), .startingRecording(let t):
      startedAt = t
    default:
      startedAt = nil
    }
    guard let startedAt else { return "00:00" }
    let elapsed = max(0, now.timeIntervalSince(startedAt))
    let total = Int(elapsed.rounded(.down))
    let m = total / 60
    let s = total % 60
    return String(format: "%02d:%02d", m, s)
  }

  private func startRecordingTimer() {
    recordingTimer?.invalidate()
    now = Date()
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.now = Date()
      }
    }
  }

  private func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
  }

  private func validateAudioFile(_ url: URL) throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
    if size <= 0 {
      throw NSError(
        domain: "NoteStream", code: 30,
        userInfo: [
          NSLocalizedDescriptionKey: "Recording file is empty."
        ])
    }
  }

  private func syncUIStateFromModelStatus() {
    guard let modelStatus else { return }
    guard modelStatus.model == selectedModel else { return }

    if case .transcribing = uiState { return }
    if case .startingRecording = uiState { return }
    if case .recording = uiState { return }
    if case .finalizingTranscript = uiState { return }

    switch modelStatus.state {
    case .idle:
      uiState = .idle
    case .downloading, .loading:
      uiState = .preparingModel(selectedModel)
    case .ready:
      uiState = .ready(selectedModel)
    case .failed(let message):
      uiState = .failed(message: message)
    }
  }
}
