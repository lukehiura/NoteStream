import Foundation
import NoteStreamCore

public actor CompositeDiagnosticsLogger: DiagnosticsLogging {
  private let loggers: [any DiagnosticsLogging]

  public init(_ loggers: [any DiagnosticsLogging]) {
    self.loggers = loggers
  }

  public func log(_ event: DiagnosticsEvent) async {
    for logger in loggers {
      await logger.log(event)
    }
  }
}
