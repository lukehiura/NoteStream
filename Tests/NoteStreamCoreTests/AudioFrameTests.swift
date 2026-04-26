import Foundation
import Testing

@testable import NoteStreamCore

@Test func audioFrameDurationSecondsMono() {
  let samples = [Float](repeating: 0, count: 16_000)
  let frame = AudioFrame(
    startTime: 0,
    samples: samples,
    sampleRateHz: 16_000,
    channelCount: 1
  )
  #expect(frame.durationSeconds == 1.0)
}

@Test func audioFrameDurationSecondsZeroSampleRate() {
  let frame = AudioFrame(startTime: 0, samples: [1, 2], sampleRateHz: 0, channelCount: 1)
  #expect(frame.durationSeconds == 0)
}
