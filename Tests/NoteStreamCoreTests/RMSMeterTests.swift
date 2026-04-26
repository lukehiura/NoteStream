import Testing

@testable import NoteStreamCore

@Test func rmsOfSilenceIsZero() async throws {
  let meter = RMSMeter()
  #expect(meter.rms(of: [0, 0, 0]) == 0)
}

@Test func rmsOfConstantSignal() async throws {
  let meter = RMSMeter()
  let value = meter.rms(of: [0.5, 0.5, 0.5])
  #expect(abs(value - 0.5) < 0.0001)
}
