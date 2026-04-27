import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import Observation
import UniformTypeIdentifiers

extension TranscriptionViewModel {
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

  func defaultSpeakerLabels(for turns: [SpeakerTurn]) -> [String: String] {
    let ids = Array(Set(turns.map(\.speakerID))).sorted()
    return Dictionary(
      uniqueKeysWithValues: ids.enumerated().map { index, id in
        (id, "Speaker \(index + 1)")
      })
  }

  func speakerLabelMap(from segments: [TranscriptSegment]) -> [String: String] {
    var labels: [String: String] = [:]
    for segment in segments {
      if let id = segment.speakerID, let name = segment.speakerName {
        labels[id] = name
      }
    }
    return labels
  }

  func applySpeakerDiarizationIfEnabled(
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

  func startLiveSpeakerDiarizationIfNeededAsync() async {
    guard liveSpeakerDiarizationEnabled, speakerDiarizationEnabled else {
      await liveSpeaker.stop()
      return
    }
    await liveSpeaker.start(expectedSpeakerCount: expectedSpeakerCount)
  }

  func stopLiveSpeakerDiarizationAsync() async {
    await liveSpeaker.stop()
  }

  func stopLiveSpeakerDiarizationSync() {
    liveSpeaker.stopSync()
  }

  func scheduleLiveDiarizationFrame(_ frame: AudioFrame) {
    guard speakerDiarizationEnabled else { return }
    liveSpeaker.ingest(frame: frame) { [weak self] in
      self?.liveTranscriptSegments ?? []
    }
  }

  private enum OllamaNotesSummarizationPolicy {
    /// If the committed transcript spans longer than this, run staged chunk summaries (local models).
    static let mergeChunkingMinSpanSeconds: TimeInterval = 600
    /// Max wall-clock span per chunk (~8 minutes).
    static let chunkMaxSpanSeconds: TimeInterval = 480
  }

  func transcriptTimeSpanSeconds(_ segments: [TranscriptSegment]) -> TimeInterval {
    let sorted = segments.filter { $0.status == .committed }.sorted { $0.startTime < $1.startTime }
    guard let first = sorted.first, let last = sorted.last else { return 0 }
    return max(0, last.endTime - first.startTime)
  }

  func shouldUseOllamaChunkedSummarization(segments: [TranscriptSegment]) -> Bool {
    guard llmProvider == .ollama else { return false }
    return transcriptTimeSpanSeconds(segments)
      > OllamaNotesSummarizationPolicy.mergeChunkingMinSpanSeconds
  }

  /// Long Ollama runs: summarize time-chunks, then one merge pass for a single `NotesSummary`.
  func summarizeWithOllamaChunking(
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

  func summarizeFinalTranscript(
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

  func cancelLiveNotesTasks() {
    liveNotes.cancel()
  }

  /// Called frequently from the rolling transcript path; interval and character gates limit work.
  func maybeUpdateLiveNotes() {
    updateLiveNotes(force: false)
  }

  func refreshLiveNotesNow() {
    updateLiveNotes(force: true)
  }

  func updateLiveNotes(force: Bool) {
    liveNotes.updateIfNeeded(
      force: force,
      context: LiveNotesCoordinator.UpdateContext(
        isRecording: isRecording,
        liveNotesEnabled: liveNotesEnabled,
        notesSummaryEnabled: notesSummaryEnabled,
        summarizer: notesSummarizer,
        committedSegments: liveTranscriptSegments,
        previousNotesMarkdown: notesMarkdown,
        intervalMinutes: liveNotesIntervalMinutes,
        minimumCharacters: liveNotesMinimumCharacters,
        preferences: notesGenerationPreferences,
        shouldChunk: shouldUseOllamaChunkedSummarization(
          segments: liveTranscriptSegments.filter { $0.status == .committed }
        )
      )
    )
  }
}
