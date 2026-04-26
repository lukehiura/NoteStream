import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct NotesEmptyState: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "sparkles")
        .font(.title)
        .foregroundStyle(.secondary)

      Text("No AI notes yet")
        .font(.headline)

      Text(model.notesSetupStatusText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if !model.notesSummaryEnabled {
        Button {
          model.enableAINotes()
        } label: {
          Label("Enable AI Notes", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
      }

      if model.notesSummaryEnabled && !model.allSegments.isEmpty {
        Button {
          model.regenerateNotesForSelectedSession()
        } label: {
          Label("Generate Notes Now", systemImage: "wand.and.stars")
        }
        .buttonStyle(.bordered)
        .disabled(!model.canRegenerateNotes)
        .help(model.notesSetupStatusText)
      }

      Button {
        model.openAINotesSettings()
      } label: {
        Label("Open AI Notes Settings", systemImage: "gearshape")
      }
      .buttonStyle(.bordered)
    }
    .padding(.top, 8)
  }
}
