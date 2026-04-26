import XCTest

@testable import NoteStreamCore

final class RMSMeterTests: XCTestCase {
  func testRmsOfSilenceIsZero() async throws {
    let meter = RMSMeter()
    XCTAssertEqual(meter.rms(of: [0, 0, 0]), 0)
  }

  func testRmsOfConstantSignal() async throws {
    let meter = RMSMeter()
    let value = meter.rms(of: [0.5, 0.5, 0.5])
    XCTAssertEqual(value, 0.5, accuracy: 0.0001)
  }
}
