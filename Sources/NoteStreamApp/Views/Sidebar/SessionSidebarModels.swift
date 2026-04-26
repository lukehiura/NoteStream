import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

enum SessionFilter: String, CaseIterable, Identifiable {
  case all
  case completed
  case partial
  case failed

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "All"
    case .completed: return "Done"
    case .partial: return "Partial"
    case .failed: return "Failed"
    }
  }
}

enum SessionSort: String, CaseIterable, Identifiable {
  case newest
  case oldest
  case longest
  case mostSegments

  var id: String { rawValue }

  var title: String {
    switch self {
    case .newest: return "Newest"
    case .oldest: return "Oldest"
    case .longest: return "Longest"
    case .mostSegments: return "Most segments"
    }
  }
}

enum SessionUIStatus: Equatable {
  case completed
  case partial
  case failed
  case empty
  case unknown

  var title: String {
    switch self {
    case .completed: return "Completed"
    case .partial: return "Partial"
    case .failed: return "Failed"
    case .empty: return "Empty"
    case .unknown: return "Unknown"
    }
  }

  var icon: String {
    switch self {
    case .completed: return "checkmark.circle.fill"
    case .partial: return "clock.badge.exclamationmark.fill"
    case .failed: return "xmark.circle.fill"
    case .empty: return "circle.dashed"
    case .unknown: return "questionmark.circle"
    }
  }

  var tint: Color {
    switch self {
    case .completed: return .green
    case .partial: return .orange
    case .failed: return .red
    case .empty: return .secondary
    case .unknown: return .secondary
    }
  }
}

extension LectureSession {
  var uiStatus: SessionUIStatus {
    switch metadata.transcriptionStatus {
    case "final_ok", nil:
      return segments.isEmpty ? .empty : .completed
    case "rolling_only":
      return .partial
    case "empty_final_transcript", "empty_rolling_transcript":
      return .empty
    case "failed":
      return .failed
    default:
      return segments.isEmpty ? .unknown : .completed
    }
  }

  var transcriptDuration: TimeInterval {
    segments.transcriptDuration
  }

  var displayTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    if trimmed.hasPrefix("Recording ") {
      return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    return trimmed
  }

  var displaySubtitle: String {
    var parts: [String] = []

    if !segments.isEmpty {
      parts.append("\(segments.count) segments")
      parts.append(TranscriptFormatting.formatDuration(transcriptDuration))
    } else {
      parts.append("No transcript")
    }

    parts.append(SessionUIFormatting.displayModelName(model))

    return parts.joined(separator: " • ")
  }
}

extension Array where Element == TranscriptSegment {
  var transcriptDuration: TimeInterval {
    guard let start = map(\.startTime).min(),
      let end = map(\.endTime).max()
    else { return 0 }

    return Swift.max(0, end - start)
  }
}
