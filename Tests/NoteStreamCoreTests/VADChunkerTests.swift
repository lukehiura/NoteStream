import Testing

@testable import NoteStreamCore

@Test func vadChunkerDoesNotEmitForSilence() async throws {
  var chunker = VADChunker()
  var emitted: NoteStreamAudioChunk?

  for i in 0..<50 {
    emitted = chunker.ingest(
      frame: AudioFrame(
        startTime: Double(i) * 0.02,
        samples: Array(repeating: 0.001, count: 320),
        sampleRateHz: 16_000,
        channelCount: 1
      ),
      isSpeechLike: false,
      config: VADChunkerConfig()
    )
  }

  #expect(emitted == nil)
}

@Test func vadChunkerEmitsAfterSpeechPause() async throws {
  var chunker = VADChunker()
  var emitted: NoteStreamAudioChunk?

  var cfg = VADChunkerConfig()
  cfg.silenceToCloseMs = 100
  cfg.minChunkSeconds = 0.1
  cfg.preRollMs = 0
  cfg.postRollMs = 0

  for i in 0..<20 {
    emitted = chunker.ingest(
      frame: AudioFrame(
        startTime: Double(i) * 0.02,
        samples: Array(repeating: 0.1, count: 320),
        sampleRateHz: 16_000,
        channelCount: 1
      ),
      isSpeechLike: true,
      config: cfg
    )
  }

  for i in 20..<40 {
    emitted = chunker.ingest(
      frame: AudioFrame(
        startTime: Double(i) * 0.02,
        samples: Array(repeating: 0.001, count: 320),
        sampleRateHz: 16_000,
        channelCount: 1
      ),
      isSpeechLike: false,
      config: cfg
    )
    if emitted != nil { break }
  }

  #expect(emitted != nil)
}
