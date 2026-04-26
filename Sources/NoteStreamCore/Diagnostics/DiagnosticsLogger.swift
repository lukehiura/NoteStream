import Foundation

public protocol DiagnosticsLogging: Sendable {
  func log(_ event: DiagnosticsEvent) async
}

public actor DiagnosticsLogger: DiagnosticsLogging {
  public static let shared = DiagnosticsLogger()

  private var sink: (any DiagnosticsLogging)?

  public init() {}

  public func setSink(_ sink: (any DiagnosticsLogging)?) {
    self.sink = sink
  }

  public func log(_ event: DiagnosticsEvent) async {
    await sink?.log(event)
  }

  public func log(
    level: DiagnosticsLevel,
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) async {
    await log(
      DiagnosticsEvent(
        level: level,
        category: category,
        message: message,
        metadata: metadata
      )
    )
  }
}

public struct NoopDiagnosticsLogger: DiagnosticsLogging {
  public init() {}
  public func log(_ event: DiagnosticsEvent) async {}
}

extension DiagnosticsLogging {
  public func debug(
    _ category: DiagnosticsCategory,
    _ message: String,
    _ metadata: [String: String] = [:]
  ) async {
    await log(
      .init(
        level: .debug,
        category: category.rawValue,
        message: message,
        metadata: metadata
      ))
  }

  public func info(
    _ category: DiagnosticsCategory,
    _ message: String,
    _ metadata: [String: String] = [:]
  ) async {
    await log(
      .init(
        level: .info,
        category: category.rawValue,
        message: message,
        metadata: metadata
      ))
  }

  public func warning(
    _ category: DiagnosticsCategory,
    _ message: String,
    _ metadata: [String: String] = [:]
  ) async {
    await log(
      .init(
        level: .warning,
        category: category.rawValue,
        message: message,
        metadata: metadata
      ))
  }

  public func error(
    _ category: DiagnosticsCategory,
    _ message: String,
    _ error: Error? = nil,
    _ metadata: [String: String] = [:]
  ) async {
    var merged = metadata

    if let error {
      let ns = error as NSError
      merged["errorDescription"] = ns.localizedDescription
      merged["errorDomain"] = ns.domain
      merged["errorCode"] = "\(ns.code)"
    }

    await log(
      .init(
        level: .error,
        category: category.rawValue,
        message: message,
        metadata: merged
      ))
  }
}
