import Foundation

public struct TranscriptSanitizer: Sendable {
  public init() {}

  public static func sanitize(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
    segments
      .map { segment in
        var cleaned = segment
        cleaned.text = normalizeWhitespace(stripWhisperTokens(cleaned.text))
        return cleaned
      }
      .filter { !$0.text.isEmpty }
      .filter { !isCommonHallucination($0.text) }
  }

  public func shouldDrop(_ text: String) -> Bool {
    let normalized = Self.normalizeWhitespace(Self.stripWhisperTokens(text))
    if normalized.isEmpty { return true }
    if Self.isCommonHallucination(normalized) { return true }
    return false
  }

  public static func cleanWhisperText(_ text: String) -> String {
    normalizeWhitespace(stripWhisperTokens(text))
  }

  private static func normalizeWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\n", with: " ")
      .split(separator: " ")
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripWhisperTokens(_ text: String) -> String {
    text.replacingOccurrences(
      of: #"<\|[^>]+\|>"#,
      with: "",
      options: .regularExpression
    )
  }

  private static func isCommonHallucination(_ text: String) -> Bool {
    let lower = normalizeWhitespace(text).lowercased()
    let banned = Set([
      "[silence]",
      "(silence)",
      "(ambient noise)",
      "[blank_audio]",
      "thank you for watching",
      "thanks for watching",
      "please subscribe",
      "like and subscribe",
    ])
    return banned.contains(lower)
  }
}
