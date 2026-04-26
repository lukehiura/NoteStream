import Foundation

enum SpeechModelDisplay {
  static func name(for raw: String) -> String {
    switch raw {
    case "tiny.en":
      return "Tiny"
    case "base.en":
      return "Fast"
    case "small.en":
      return "Balanced"
    case "medium.en":
      return "Accurate"
    default:
      return fallback(raw)
    }
  }

  static func compactName(for raw: String) -> String {
    switch raw {
    case "tiny.en":
      return "Tiny"
    case "base.en":
      return "Fast"
    case "small.en":
      return "Bal"
    case "medium.en":
      return "Acc"
    default:
      return fallback(raw)
    }
  }

  private static func fallback(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: ".en", with: "")
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }
}
