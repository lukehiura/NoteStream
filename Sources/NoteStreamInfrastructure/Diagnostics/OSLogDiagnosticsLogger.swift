import Foundation
import NoteStreamCore
import OSLog

public actor OSLogDiagnosticsLogger: DiagnosticsLogging {
  private let logger = Logger(subsystem: "com.notestream.app", category: "diagnostics")

  public init() {}

  public func log(_ event: DiagnosticsEvent) async {
    let sanitized = DiagnosticsRedactor.sanitize(event)
    let redacted = sanitized.metadata

    let metadataText =
      redacted
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: " ")

    let text = "[\(sanitized.category)] \(sanitized.message) \(metadataText)"

    switch sanitized.level {
    case .debug:
      logger.debug("\(text, privacy: .private)")
    case .info:
      logger.info("\(text, privacy: .private)")
    case .warning:
      logger.warning("\(text, privacy: .private)")
    case .error:
      logger.error("\(text, privacy: .private)")
    }
  }
}
