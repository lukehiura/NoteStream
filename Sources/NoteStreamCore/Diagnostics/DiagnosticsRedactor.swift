import Foundation

public enum DiagnosticsRedactor {
  private static let sensitiveKeys: Set<String> = [
    "apiKey",
    "authorization",
    "token",
    "password",
    "secret",
    "transcript",
    "transcriptText",
    "transcriptMarkdown",
    "prompt",
    "responseText",
    "notesMarkdown",
    "summaryMarkdown",
  ]

  public static func redact(_ metadata: [String: String]) -> [String: String] {
    metadata.reduce(into: [:]) { result, pair in
      let key = pair.key
      let lowered = key.lowercased()

      if sensitiveKeys.contains(key) || sensitiveKeys.contains(lowered) {
        result[key] = "<redacted>"
      } else if looksLikeAPIKey(pair.value) {
        result[key] = "<redacted>"
      } else {
        result[key] = pair.value
      }
    }
  }

  /// Best-effort scrub for log lines that are not structured metadata (messages, summaries).
  public static func redactLogMessage(_ message: String) -> String {
    if looksLikeAPIKey(message) {
      return "<redacted>"
    }
    if message.contains("sk-") || message.contains("sk-ant-") {
      return "<redacted: possible API key material>"
    }
    if message.count > 500 {
      return String(message.prefix(200)) + " … (\(message.count) chars omitted)"
    }
    return message
  }

  /// Full event safe for file / in-memory / OSLog sinks.
  public static func sanitize(_ event: DiagnosticsEvent) -> DiagnosticsEvent {
    DiagnosticsEvent(
      id: event.id,
      timestamp: event.timestamp,
      level: event.level,
      category: event.category,
      message: redactLogMessage(event.message),
      metadata: redact(event.metadata)
    )
  }

  private static func looksLikeAPIKey(_ value: String) -> Bool {
    value.hasPrefix("sk-")
      || value.hasPrefix("sk-ant-")
      || (value.count > 80 && value.contains("."))
  }
}
