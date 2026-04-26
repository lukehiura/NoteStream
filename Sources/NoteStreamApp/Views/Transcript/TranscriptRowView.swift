import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptRowView: View {
  let segment: TranscriptSegment
  let currentPlaybackTime: TimeInterval
  let onSeek: (TimeInterval) -> Void
  let onUpdateText: (UUID, String) -> Void
  let onDelete: (UUID) -> Void
  let onMergePrevious: (UUID) -> Void
  let onSplit: (UUID, Int) -> Void
  let onRenameSpeakerID: (String) -> Void

  @State private var isHovering = false
  @State private var copiedLine = false
  @State private var isEditing = false
  @State private var editText = ""
  @State private var editCursorOffset: Int?

  private var speakerLabel: String? {
    let s = segment.speakerName ?? segment.speakerID
    guard let s, !s.isEmpty else { return nil }
    return s
  }

  private var isCurrentSegment: Bool {
    currentPlaybackTime >= segment.startTime && currentPlaybackTime <= segment.endTime
  }

  private var canSplitAtCursor: Bool {
    guard let editCursorOffset else { return false }
    return editCursorOffset > 0 && editCursorOffset < editText.count
  }

  private var lineForClipboard: String {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let speakerLabel {
      return "[\(TranscriptFormatting.formatTimestamp(segment.startTime))] \(speakerLabel): \(text)"
    }
    return "[\(TranscriptFormatting.formatTimestamp(segment.startTime))] \(text)"
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(TranscriptFormatting.formatTimestamp(segment.startTime))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.12))
        .clipShape(Capsule())
        .frame(width: 62, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
          onSeek(segment.startTime)
        }

      VStack(alignment: .leading, spacing: 6) {
        if let speakerLabel {
          Text(speakerLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
            .contextMenu {
              if let sid = segment.speakerID {
                Button("Rename speaker…") {
                  onRenameSpeakerID(sid)
                }
              }
            }
        }

        if isEditing {
          CursorTrackingTextEditor(
            text: $editText,
            cursorOffset: $editCursorOffset
          )
          .frame(minHeight: 90)
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(.secondary.opacity(0.2))
          )

          HStack {
            Button("Save") {
              onUpdateText(segment.id, editText)
              isEditing = false
            }

            Button("Split at Cursor") {
              if let editCursorOffset {
                onSplit(segment.id, editCursorOffset)
                isEditing = false
              }
            }
            .disabled(!canSplitAtCursor)

            Button("Cancel", role: .cancel) {
              isEditing = false
            }
          }
        } else {
          Text(segment.text)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)

          if segment.status == .draft {
            Text("Draft")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer(minLength: 8)

      if isHovering {
        Button {
          ClipboardExporter.copyToClipboard(text: lineForClipboard)
          copiedLine = true

          Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
              copiedLine = false
            }
          }
        } label: {
          Image(systemName: copiedLine ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(copiedLine ? "Copied" : "Copy line")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(
          isCurrentSegment
            ? Color.accentColor.opacity(0.12)
            : (isHovering ? Color.primary.opacity(0.045) : Color.clear)
        )
    )
    .contentShape(Rectangle())
    .contextMenu {
      Button("Edit") {
        editText = segment.text
        editCursorOffset = segment.text.count
        isEditing = true
      }

      Button("Merge with previous") {
        onMergePrevious(segment.id)
      }

      if let sid = segment.speakerID {
        Button("Rename speaker…") {
          onRenameSpeakerID(sid)
        }
      }

      Button("Split in middle") {
        let n = segment.text.count
        guard n > 1 else { return }
        onSplit(segment.id, max(1, n / 2))
      }
      .disabled(segment.text.count < 2)

      Divider()

      Button("Delete segment", role: .destructive) {
        onDelete(segment.id)
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovering = hovering
      }
    }
  }
}
