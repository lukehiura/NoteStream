import Foundation
import NoteStreamCore
import Observation

@MainActor
@Observable
final class LiveSpeakerCoordinator {
  var isActive: Bool = false
  var statusText: String?

  private var diarizer: (any LiveSpeakerDiarizing)?
  private var turns: [SpeakerTurn] = []
  private var ingestTask: Task<Void, Never>?

  var onRelabel: ((Set<UUID>, [UUID: TranscriptSegment]) -> Void)?
  var onError: ((Error) -> Void)?

  func setDiarizer(_ diarizer: (any LiveSpeakerDiarizing)?) {
    self.diarizer = diarizer
  }

  func start(expectedSpeakerCount: Int) async {
    guard let diarizer else {
      isActive = false
      statusText = "Live speaker labels require a real diarizer tool."
      return
    }

    turns = []
    isActive = true
    statusText = "Live speaker labeling active"

    do {
      try await diarizer.start(expectedSpeakerCount: expectedSpeakerCount)
    } catch {
      isActive = false
      statusText = "Live speaker setup failed."
      onError?(error)
    }
  }

  func stop() async {
    ingestTask?.cancel()
    ingestTask = nil
    isActive = false

    if let diarizer = diarizer {
      _ = try? await diarizer.finish()
      await diarizer.reset()
    }

    turns = []
    statusText = nil
  }

  func stopSync() {
    ingestTask?.cancel()
    ingestTask = nil
    isActive = false
    turns = []
    statusText = nil
    let diarizer = self.diarizer
    Task {
      await diarizer?.reset()
    }
  }

  func ingest(
    frame: AudioFrame,
    liveTranscriptSegmentsProvider: @escaping @MainActor () -> [TranscriptSegment]
  ) {
    guard isActive, let diarizer else { return }

    Task.detached(priority: .utility) { [weak self] in
      do {
        guard let update = try await diarizer.ingest(frame: frame) else { return }
        await MainActor.run { [weak self] in
          self?.applyUpdate(update, liveTranscriptSegments: liveTranscriptSegmentsProvider())
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.statusText = "Live speaker update failed: \(error.localizedDescription)"
          self?.onError?(error)
        }
      }
    }
  }

  private func applyUpdate(
    _ update: LiveSpeakerDiarizationUpdate,
    liveTranscriptSegments: [TranscriptSegment]
  ) {
    mergeTurns(update.turns)
    relabelRecentSegments(
      windowStart: update.windowStartTime,
      liveTranscriptSegments: liveTranscriptSegments
    )
  }

  private func mergeTurns(_ newTurns: [SpeakerTurn]) {
    guard !newTurns.isEmpty else { return }

    let minStart = newTurns.map(\.startTime).min() ?? 0
    let maxEnd = newTurns.map(\.endTime).max() ?? minStart

    turns.removeAll { turn in
      !(turn.endTime <= minStart || turn.startTime >= maxEnd)
    }
    turns.append(contentsOf: newTurns)
    turns.sort { $0.startTime < $1.startTime }
  }

  private func relabelRecentSegments(
    windowStart: TimeInterval,
    liveTranscriptSegments: [TranscriptSegment]
  ) {
    guard !turns.isEmpty else { return }

    let labels = defaultSpeakerLabels(for: turns)
    let recentSegments = liveTranscriptSegments.filter { $0.endTime >= windowStart }
    let recentIDs = Set(recentSegments.map(\.id))

    let relabeledRecent = SpeakerTurnAligner.assignSpeakers(
      segments: recentSegments,
      turns: turns,
      speakerLabels: labels
    )
    let relabeledByID = Dictionary(uniqueKeysWithValues: relabeledRecent.map { ($0.id, $0) })

    onRelabel?(recentIDs, relabeledByID)
  }

  private func defaultSpeakerLabels(for turns: [SpeakerTurn]) -> [String: String] {
    let ids = Array(Set(turns.map(\.speakerID))).sorted()
    return Dictionary(
      uniqueKeysWithValues: ids.enumerated().map { index, id in
        (id, "Speaker \(index + 1)")
      })
  }
}
