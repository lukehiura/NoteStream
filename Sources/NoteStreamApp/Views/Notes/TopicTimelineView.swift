import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct TopicTimelineView: View {
  let items: [TopicTimelineItem]
  let onSeek: (TimeInterval) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !items.isEmpty {
        Divider()

        Text("Topic Timeline")
          .font(.headline)

        ForEach(items) { item in
          Button {
            onSeek(item.startTime)
          } label: {
            HStack(alignment: .top, spacing: 8) {
              Text(DurationFormatting.timestamp(item.startTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.callout.weight(.semibold))

                if let summary = item.summary, !summary.isEmpty {
                  Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer()
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
