import Foundation
import XCTest

@testable import NoteStreamCore

final class AudioFrameTests: XCTestCase {
  func testAudioFrameDurationSecondsMono() {
    let samples = [Float](repeating: 0, count: 16_000)
    let frame = AudioFrame(
      startTime: 0,
      samples: samples,
      sampleRateHz: 16_000,
      channelCount: 1
    )
    XCTAssertEqual(frame.durationSeconds, 1.0)
  }

  func testAudioFrameDurationSecondsZeroSampleRate() {
    let frame = AudioFrame(startTime: 0, samples: [1, 2], sampleRateHz: 0, channelCount: 1)
    XCTAssertEqual(frame.durationSeconds, 0)
  }
}
