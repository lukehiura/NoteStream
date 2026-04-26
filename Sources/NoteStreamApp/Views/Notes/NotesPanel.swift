import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct NotesPanel: View {
  @Bindable var model: TranscriptionViewModel

  private var liveNotesChromeActive: Bool {
    model.liveCaptureShowsRecordingChrome && model.liveNotesEnabled
  }

  private var notesProgressBusy: Bool {
    model.notesStatusText == "Generating notes…"
      || model.notesStatusText == "Regenerating notes…"
      || (model.isGeneratingLiveNotes && !liveNotesChromeActive)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(liveNotesChromeActive ? "Live Notes" : "Notes")
          .font(.headline)

        Spacer(minLength: 8)

        if notesProgressBusy {
          ProgressView()
            .controlSize(.small)
        }
      }

      if liveNotesChromeActive {
        HStack(spacing: 8) {
          if model.isGeneratingLiveNotes {
            ProgressView()
              .controlSize(.small)
          }

          Text(model.liveNotesStatusDisplayText)
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          Button("Refresh Now") {
            model.refreshLiveNotesNow()
          }
          .disabled(!model.canRefreshLiveNotesNow)
        }
        .padding(.vertical, 2)

        Text("Live notes are provisional. Final notes replace them after Stop & Transcribe.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if let status = model.notesStatusText {
        Text(status)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !model.notesSummaryEnabled {
        Label("AI notes are off", systemImage: "pause.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.orange)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(Color.orange.opacity(0.12))
          .clipShape(Capsule())
      }

      HStack(spacing: 10) {
        Button {
          model.enableAINotes()
        } label: {
          Label("Enable", systemImage: "sparkles")
        }
        .disabled(model.notesSummaryEnabled)

        Button {
          model.regenerateNotesForSelectedSession()
        } label: {
          Label("Generate Notes Now", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canRegenerateNotes)
        .help(model.notesSetupStatusText)

        Button {
          ClipboardExporter.copyToClipboard(text: model.notesMarkdown)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(model.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Spacer()

        Button {
          model.openAINotesSettings()
        } label: {
          Image(systemName: "gearshape")
        }
        .help("AI Notes settings")
      }

      Divider()

      if model.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NotesEmptyState(model: model)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        Text(model.notesSetupStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)

        ScrollView {
          Text(.init(model.notesMarkdown))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
      }

      TopicTimelineView(items: model.topicTimeline) { time in
        model.seekPlayback(to: time)
      }

      AskRecordingPanel(model: model)
    }
    .padding(14)
    .background(AppSurface.panel)
  }
}
