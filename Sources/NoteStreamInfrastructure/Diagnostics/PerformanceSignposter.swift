import OSLog

/// Lightweight Instruments signposts for expensive operations.
public struct PerformanceSignposter: Sendable {
  private let signposter: OSSignposter

  public init(subsystem: String = "com.notestream.app", category: String) {
    self.signposter = OSSignposter(subsystem: subsystem, category: category)
  }

  public func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
    signposter.beginInterval(name)
  }

  public func endInterval(_ name: StaticString, state: OSSignpostIntervalState) {
    signposter.endInterval(name, state)
  }
}
