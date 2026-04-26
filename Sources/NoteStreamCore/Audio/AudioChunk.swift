import Foundation

/// A speech-bounded chunk suitable for transcription.
/// Samples are expected to be 16kHz mono Float32 normalized to [-1, 1].
public struct NoteStreamAudioChunk: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var startTime: TimeInterval
  public var endTime: TimeInterval
  public var samples: [Float]
  public var sampleRateHz: Int

  public init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    endTime: TimeInterval,
    samples: [Float],
    sampleRateHz: Int = 16_000
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.samples = samples
    self.sampleRateHz = sampleRateHz
  }
}
