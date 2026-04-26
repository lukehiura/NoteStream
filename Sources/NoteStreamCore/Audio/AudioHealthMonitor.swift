import Foundation

/// Lightweight rolling-window heuristic for detecting "captured-but-silent" audio.
/// Designed for real-time pipelines where DRM-protected audio often appears as near-zero RMS.
public struct AudioHealthMonitor: Sendable {
  private struct Observation: Sendable {
    let time: TimeInterval
    let isSilent: Bool
  }

  private var observations: [Observation] = []
  private var lastIngestTime: TimeInterval?

  public private(set) var currentState: AudioInputHealth = .ok

  // Configurable hysteresis limits
  private let windowSeconds: TimeInterval
  private let silenceThresholdPercent: Double
  private let stallTimeoutSeconds: TimeInterval
  private let epsilon: Float

  public init(
    windowSeconds: TimeInterval = 2.0,
    silenceThresholdPercent: Double = 0.95,
    stallTimeoutSeconds: TimeInterval = 3.0,
    epsilon: Float = 1e-5
  ) {
    self.windowSeconds = windowSeconds
    self.silenceThresholdPercent = silenceThresholdPercent
    self.stallTimeoutSeconds = stallTimeoutSeconds
    self.epsilon = epsilon
  }

  public mutating func ingest(time: TimeInterval, rms: Float) -> AudioInputHealth {
    if let last = lastIngestTime, (time - last) > stallTimeoutSeconds {
      currentState = .stalled
    }
    lastIngestTime = time

    // Prune old observations outside the window.
    observations.removeAll { time - $0.time > windowSeconds }

    // Classify the current frame (epsilon handles mixer dither).
    let isSilent = rms <= epsilon
    observations.append(.init(time: time, isSilent: isSilent))

    // Calculate silence density (require at least a few frames to make a decision).
    if observations.count > 10 {
      let silentCount = observations.reduce(into: 0) { acc, obs in
        if obs.isSilent { acc += 1 }
      }
      let silentRatio = Double(silentCount) / Double(observations.count)

      // Apply hysteresis.
      if silentRatio >= silenceThresholdPercent {
        currentState = .silentSuspected
      } else if silentRatio < 0.20 {
        currentState = .ok
      }
    }

    return currentState
  }
}
