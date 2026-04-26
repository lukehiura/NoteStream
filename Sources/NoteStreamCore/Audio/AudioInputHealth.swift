import Foundation

public enum AudioInputHealth: String, Codable, Sendable, Equatable {
  case ok
  case silentSuspected
  case stalled
}
