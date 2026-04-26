import Foundation

public struct VADChunkerConfig: Sendable, Equatable {
  public var silenceToCloseMs: Int = 600
  public var minChunkSeconds: TimeInterval = 1.5
  public var maxChunkSeconds: TimeInterval = 5
  public var preRollMs: Int = 0
  public var postRollMs: Int = 0

  public init() {}
}

/// Converts a stream of frames + speech/silence state into speech-bounded chunks.
public struct VADChunker: Sendable {
  private var currentSamples: [Float] = []
  private var currentStartTime: TimeInterval?
  private var currentSampleRateHz: Int?

  private var lastSpeechLikeTime: TimeInterval?
  private var isInSpeech: Bool = false

  public init() {}

  public mutating func ingest(
    frame: AudioFrame,
    isSpeechLike: Bool,
    config: VADChunkerConfig
  ) -> NoteStreamAudioChunk? {
    let sampleFrames = frame.samples.count / max(1, frame.channelCount)
    let frameDuration = TimeInterval(sampleFrames) / TimeInterval(frame.sampleRateHz)
    let frameEnd = frame.startTime + frameDuration

    if isSpeechLike {
      lastSpeechLikeTime = frameEnd
      if !isInSpeech {
        isInSpeech = true
        currentStartTime = max(0, frame.startTime - TimeInterval(config.preRollMs) / 1000)
        currentSampleRateHz = frame.sampleRateHz
        currentSamples = []
      }
    }

    if isInSpeech {
      currentSamples.append(contentsOf: frame.samples)
    }

    guard isInSpeech, let start = currentStartTime else { return nil }

    let elapsed = frameEnd - start

    // Force close if too long.
    if elapsed >= config.maxChunkSeconds {
      return closeChunk(endTime: frameEnd, config: config)
    }

    // Close on sustained silence.
    if let last = lastSpeechLikeTime {
      let silenceMs = (frameEnd - last) * 1000
      if silenceMs >= Double(config.silenceToCloseMs) && elapsed >= config.minChunkSeconds {
        return closeChunk(endTime: frameEnd, config: config)
      }
    }

    return nil
  }

  private mutating func closeChunk(endTime: TimeInterval, config: VADChunkerConfig)
    -> NoteStreamAudioChunk?
  {
    guard let start = currentStartTime, let sr = currentSampleRateHz else { return nil }

    let postRollSeconds = TimeInterval(config.postRollMs) / 1000
    let finalEnd = endTime + postRollSeconds

    let chunk = NoteStreamAudioChunk(
      startTime: start,
      endTime: finalEnd,
      samples: currentSamples,
      sampleRateHz: sr
    )

    currentSamples = []
    currentStartTime = nil
    currentSampleRateHz = nil
    lastSpeechLikeTime = nil
    isInSpeech = false
    return chunk
  }
}
