import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SessionSidebarRow: View {
  let session: LectureSession
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 9) {
      RoundedRectangle(cornerRadius: 2)
        .fill(isSelected ? Color.accentColor : Color.clear)
        .frame(width: 3)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(session.displayTitle)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(session.displayTitle)

          Spacer(minLength: 4)

          SessionListStatusPill(status: session.uiStatus)
        }

        Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(session.displaySubtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }
}

struct SessionListStatusPill: View {
  let status: SessionUIStatus

  var body: some View {
    Image(systemName: status.icon)
      .font(.caption2)
      .foregroundStyle(status.tint)
      .padding(4)
      .background(status.tint.opacity(0.12))
      .clipShape(Circle())
      .help(status.title)
      .accessibilityLabel(status.title)
  }
}
