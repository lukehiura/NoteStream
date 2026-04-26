import Foundation

public struct RMSMeter: Sendable {
  public init() {}

  public func rms(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for s in samples {
      sum += s * s
    }
    return sqrt(sum / Float(samples.count))
  }
}
