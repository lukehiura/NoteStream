import Foundation

/// Forward-looking scaffolding for Phase 3 rolling transcription.
/// Phase 1 (file transcription) does not wire VAD into the pipeline yet.
public struct VADConfig: Sendable, Equatable {
  public var minSpeechMs: Int = 200
  public var minSilenceMsToEndSpeech: Int = 900
  public var minChunkSeconds: TimeInterval = 2
  public var idealChunkSeconds: TimeInterval = 10
  public var maxChunkSeconds: TimeInterval = 20
  public var preRollMs: Int = 300
  public var postRollMs: Int = 500

  public init() {}
}

public enum VADState: Sendable, Equatable {
  case silence
  case speech
}

/// Intentionally minimal VAD state machine.
/// Input is a stream of (time, rms) values computed from audio buffers.
public struct SimpleVAD: Sendable {
  public private(set) var state: VADState = .silence
  public private(set) var noiseFloorRMS: Double = 0.01

  private var speechStartTime: TimeInterval?
  private var lastAboveThresholdTime: TimeInterval?
  private var lastBelowThresholdTime: TimeInterval?

  public var thresholdOffset: Double = 0.025

  public init() {}

  public mutating func calibrateNoiseFloor(with rms: Double, alpha: Double = 0.02) {
    // Exponential moving average; only call during known-silence windows.
    noiseFloorRMS = (1 - alpha) * noiseFloorRMS + alpha * rms
  }

  public mutating func ingestRMS(time: TimeInterval, rms: Double, config: VADConfig) -> VADState {
    let threshold = noiseFloorRMS + thresholdOffset
    let isSpeechLike = rms > threshold

    if isSpeechLike {
      lastAboveThresholdTime = time
      if state == .silence {
        if speechStartTime == nil { speechStartTime = time }
        // Promote to speech once it stays above threshold long enough.
        if let start = speechStartTime, (time - start) * 1000 >= Double(config.minSpeechMs) {
          state = .speech
        }
      }
    } else {
      lastBelowThresholdTime = time
      speechStartTime = nil
      if state == .speech {
        // Demote back to silence after sustained quiet.
        if let lastLoud = lastAboveThresholdTime,
          (time - lastLoud) * 1000 >= Double(config.minSilenceMsToEndSpeech)
        {
          state = .silence
        }
      }
    }

    return state
  }
}
