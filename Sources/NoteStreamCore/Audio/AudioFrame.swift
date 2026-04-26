import Foundation

/// A short slice of audio with an absolute start time.
/// Samples are Float32 normalized to [-1, 1].
public struct AudioFrame: Sendable, Equatable {
  public var startTime: TimeInterval
  public var samples: [Float]
  public var sampleRateHz: Int
  public var channelCount: Int

  public init(
    startTime: TimeInterval,
    samples: [Float],
    sampleRateHz: Int,
    channelCount: Int
  ) {
    self.startTime = startTime
    self.samples = samples
    self.sampleRateHz = sampleRateHz
    self.channelCount = channelCount
  }

  /// Wall-clock span of this frame in seconds (contiguous samples).
  public var durationSeconds: TimeInterval {
    guard sampleRateHz > 0, channelCount > 0 else { return 0 }
    let frameCount = samples.count / max(1, channelCount)
    return TimeInterval(frameCount) / TimeInterval(sampleRateHz)
  }
}
