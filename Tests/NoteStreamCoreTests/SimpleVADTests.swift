import Foundation
import Testing

@testable import NoteStreamCore

@Test func staysSilentBelowThreshold() async throws {
  var vad = SimpleVAD()
  let config = VADConfig()

  var state: VADState = .silence
  for i in 0..<50 {
    let t = TimeInterval(i) * 0.02  // 20ms frames
    state = vad.ingestRMS(time: t, rms: 0.005, config: config)
  }
  #expect(state == .silence)
}

@Test func promotesToSpeechAfterMinSpeechMs() async throws {
  var vad = SimpleVAD()
  var config = VADConfig()
  config.minSpeechMs = 200

  vad.calibrateNoiseFloor(with: 0.005, alpha: 1.0)

  var state: VADState = .silence
  for i in 0..<20 {  // 20 * 20ms = 400ms
    let t = TimeInterval(i) * 0.02
    state = vad.ingestRMS(time: t, rms: 0.05, config: config)
  }
  #expect(state == .speech)
}

@Test func returnsToSilenceAfterMinSilenceMs() async throws {
  var vad = SimpleVAD()
  var config = VADConfig()
  config.minSpeechMs = 50
  config.minSilenceMsToEndSpeech = 200

  vad.calibrateNoiseFloor(with: 0.005, alpha: 1.0)

  _ = vad.ingestRMS(time: 0.00, rms: 0.05, config: config)
  _ = vad.ingestRMS(time: 0.06, rms: 0.05, config: config)

  var state: VADState = .speech
  for i in 0..<20 {  // 400ms of silence
    let t = 0.10 + TimeInterval(i) * 0.02
    state = vad.ingestRMS(time: t, rms: 0.005, config: config)
  }
  #expect(state == .silence)
}
