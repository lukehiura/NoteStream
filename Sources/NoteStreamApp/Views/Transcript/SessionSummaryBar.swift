import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SessionSummaryBar: View {
  let title: String
  let status: String
  let modelName: String
  let segmentCount: Int
  let duration: String
  let speakerSummary: String

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .lineLimit(1)

        Text("Current transcript")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      SummaryMetric(label: "Status", value: status)
      SummaryMetric(label: "Segments", value: "\(segmentCount)")
      SummaryMetric(label: "Duration", value: duration)
      SummaryMetric(label: "Speakers", value: speakerSummary)
      SummaryMetric(label: "Model", value: modelName)
    }
    .padding(12)
    .background(AppSurface.elevatedCard)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(AppSurface.separator.opacity(0.55), lineWidth: 1)
    )
  }
}

struct SummaryMetric: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)

      Text(value)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
  }
}

struct CopyToast: View {
  var body: some View {
    Label("Copied", systemImage: "checkmark.circle.fill")
      .font(.callout.weight(.semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.regularMaterial)
      .clipShape(Capsule())
      .shadow(radius: 8)
  }
}
