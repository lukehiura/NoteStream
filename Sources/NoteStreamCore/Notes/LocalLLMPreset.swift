import Foundation

/// Preset for choosing a local Ollama model without manual tuning.
public enum LocalLLMPreset: String, CaseIterable, Identifiable, Codable, Sendable {
  case auto
  case smallMac
  case balancedMac
  case highQualityMac
  case custom

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .auto: return "Auto"
    case .smallMac: return "Small Mac"
    case .balancedMac: return "Balanced Mac"
    case .highQualityMac: return "High Quality Mac"
    case .custom: return "Custom"
    }
  }
}
