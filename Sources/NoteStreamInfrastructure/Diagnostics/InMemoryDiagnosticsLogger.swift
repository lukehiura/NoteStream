import Foundation
import NoteStreamCore

/// Ring buffer of recent diagnostics for in-app UI (also redacts sensitive metadata).
public actor InMemoryDiagnosticsLogger: DiagnosticsLogging {
  private let capacity: Int
  private var events: [DiagnosticsEvent] = []

  public init(capacity: Int = 500) {
    self.capacity = max(10, capacity)
  }

  public func log(_ event: DiagnosticsEvent) async {
    events.append(DiagnosticsRedactor.sanitize(event))

    if events.count > capacity {
      events.removeFirst(events.count - capacity)
    }
  }

  public func recentEvents() -> [DiagnosticsEvent] {
    events
  }

  public func clear() {
    events.removeAll()
  }
}
