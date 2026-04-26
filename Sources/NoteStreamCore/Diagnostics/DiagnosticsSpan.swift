import Foundation

public struct DiagnosticsSpan: Sendable {
  private let diagnostics: any DiagnosticsLogging
  private let category: DiagnosticsCategory
  private let name: String
  private let start: Date
  private let metadata: [String: String]

  public init(
    diagnostics: any DiagnosticsLogging,
    category: DiagnosticsCategory,
    name: String,
    metadata: [String: String] = [:]
  ) {
    self.diagnostics = diagnostics
    self.category = category
    self.name = name
    self.start = Date()
    self.metadata = metadata
  }

  public func end(
    result: String = "ok",
    extraMetadata: [String: String] = [:]
  ) async {
    var merged = metadata
    for (key, value) in extraMetadata {
      merged[key] = value
    }

    merged["result"] = result
    merged["durationMs"] = String(format: "%.0f", Date().timeIntervalSince(start) * 1000)

    await diagnostics.info(category, "\(name)_completed", merged)
  }

  public func fail(
    _ error: Error,
    extraMetadata: [String: String] = [:]
  ) async {
    var merged = metadata
    for (key, value) in extraMetadata {
      merged[key] = value
    }

    merged["durationMs"] = String(format: "%.0f", Date().timeIntervalSince(start) * 1000)

    await diagnostics.error(category, "\(name)_failed", error, merged)
  }
}
