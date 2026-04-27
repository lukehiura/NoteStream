import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
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

  func makeDiagnosticsBundle() async throws -> URL {
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

  func setUIState(
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
}

extension TranscriptionViewModel {
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

  var recordingElapsedText: String {
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

  func startRecordingTimer() {
    recordingTimer?.invalidate()
    now = Date()
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.now = Date()
      }
    }
  }

  func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
  }

  func validateAudioFile(_ url: URL) throws {
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

  func syncUIStateFromModelStatus() {
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
