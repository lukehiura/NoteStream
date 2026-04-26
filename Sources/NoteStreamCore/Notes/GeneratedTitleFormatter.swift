import Foundation

/// Normalizes AI-generated session titles for filesystem and UI safety.
public enum GeneratedTitleFormatter {
  private static let bannedWholeTitles: Set<String> = [
    "summary",
    "recording",
    "transcript",
    "untitled recording",
  ]

  public static func sanitize(_ raw: String, maxLength: Int = 72) -> String? {
    var title = raw
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    while title.contains("  ") {
      title = title.replacingOccurrences(of: "  ", with: " ")
    }

    let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
    title = title.components(separatedBy: forbidden).joined(separator: " ")

    while title.contains("  ") {
      title = title.replacingOccurrences(of: "  ", with: " ")
    }

    title = title.trimmingCharacters(in: .whitespacesAndNewlines)

    guard title.count >= 4 else { return nil }

    let lowered = title.lowercased()
    if bannedWholeTitles.contains(lowered) {
      return nil
    }

    if title.count > maxLength {
      let idx = title.index(title.startIndex, offsetBy: maxLength)
      title = String(title[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
      if title.count > 3 {
        title += "…"
      } else {
        return nil
      }
    }

    return title
  }
}
