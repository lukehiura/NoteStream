import Foundation
import NoteStreamCore

/// Periodically exports a rolling buffer of frames to a temp file and reuses a batch ``SpeakerDiarizing`` tool.
public actor RollingWindowSpeakerDiarizer: LiveSpeakerDiarizing {
  private let batchDiarizer: any SpeakerDiarizing
  private let diagnostics: any DiagnosticsLogging

  private var expectedSpeakerCount: Int?
  private var bufferedFrames: [AudioFrame] = []
  private var lastRunEndTime: TimeInterval = 0

  private let windowSeconds: TimeInterval
  private let minIntervalSeconds: TimeInterval

  public init(
    batchDiarizer: any SpeakerDiarizing,
    windowSeconds: TimeInterval = 60,
    minIntervalSeconds: TimeInterval = 20,
    diagnostics: any DiagnosticsLogging = NoopDiagnosticsLogger()
  ) {
    self.batchDiarizer = batchDiarizer
    self.windowSeconds = windowSeconds
    self.minIntervalSeconds = minIntervalSeconds
    self.diagnostics = diagnostics
  }

  public func start(expectedSpeakerCount: Int?) async throws {
    self.expectedSpeakerCount = expectedSpeakerCount
    bufferedFrames = []
    lastRunEndTime = 0
  }

  public func ingest(frame: AudioFrame) async throws -> LiveSpeakerDiarizationUpdate? {
    bufferedFrames.append(frame)

    let currentEnd = frame.startTime + frame.durationSeconds
    let earliestAllowed = max(0, currentEnd - windowSeconds)
    bufferedFrames.removeAll { $0.startTime + $0.durationSeconds < earliestAllowed }

    guard currentEnd - lastRunEndTime >= minIntervalSeconds else {
      return nil
    }

    guard let update = try await diarizeCurrentWindow(currentEnd: currentEnd) else {
      return nil
    }

    lastRunEndTime = currentEnd
    return update
  }

  public func finish() async throws -> LiveSpeakerDiarizationUpdate? {
    guard let last = bufferedFrames.last else { return nil }
    let currentEnd = last.startTime + last.durationSeconds
    return try await diarizeCurrentWindow(currentEnd: currentEnd)
  }

  public func reset() async {
    bufferedFrames = []
    lastRunEndTime = 0
    expectedSpeakerCount = nil
  }

  private func diarizeCurrentWindow(currentEnd: TimeInterval) async throws
    -> LiveSpeakerDiarizationUpdate?
  {
    guard !bufferedFrames.isEmpty else { return nil }

    let windowStart = bufferedFrames.first?.startTime ?? max(0, currentEnd - windowSeconds)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("notestream-live-diarization-\(UUID().uuidString).caf")

    try AudioFrameCAFWriter.write(frames: bufferedFrames, to: tempURL)

    defer {
      try? FileManager.default.removeItem(at: tempURL)
    }

    let result = try await batchDiarizer.diarize(
      audioURL: tempURL,
      expectedSpeakerCount: expectedSpeakerCount
    )

    let timeOffset = windowStart
    let shiftedTurns = result.turns.map { turn -> SpeakerTurn in
      SpeakerTurn(
        id: turn.id,
        startTime: turn.startTime + timeOffset,
        endTime: turn.endTime + timeOffset,
        speakerID: turn.speakerID,
        confidence: turn.confidence
      )
    }

    await diagnostics.info(
      .diarization,
      "live_window_diarization_completed",
      [
        "turns": "\(shiftedTurns.count)",
        "windowStart": "\(windowStart)",
        "windowEnd": "\(currentEnd)",
      ])

    return LiveSpeakerDiarizationUpdate(
      turns: shiftedTurns,
      isFinalForWindow: false,
      windowStartTime: windowStart,
      windowEndTime: currentEnd
    )
  }
}
