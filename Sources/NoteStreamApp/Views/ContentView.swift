import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var model = TranscriptionViewModel()
  @State private var followTail: Bool = true

  @State private var copiedTranscript: Bool = false

  @State private var showingRename: Bool = false
  @State private var renameTargetID: UUID?
  @State private var renameText: String = ""

  @State private var showingRenameSpeaker = false
  @State private var renameSpeakerTargetID: String?
  @State private var renameSpeakerFieldText = ""

  @State private var showingNotesPanel: Bool = true

  @AppStorage("sidebarColumnWidth") private var sidebarColumnWidth: Double = 260
  @AppStorage("notesColumnWidth") private var notesColumnWidth: Double = 360

  @State private var sidebarDragStartWidth: Double?
  @State private var notesDragStartWidth: Double?

  var body: some View {
    ZStack(alignment: .topTrailing) {
      appLayout

      if copiedTranscript {
        CopyToast()
          .padding(.top, 14)
          .padding(.trailing, 18)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.2), value: copiedTranscript)
    .background(AppSurface.window)
    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
      model.handleDrop(providers: providers)
    }
    .task {
      model.prepareSelectedModelIfNeeded()
      model.checkForRecoverableRecordings()
      model.showOnboardingIfNeeded()
    }
    .sheet(isPresented: $model.showingSettingsPanel) {
      SettingsPanel(model: model)
        .frame(width: 900, height: 680)
    }
    .sheet(isPresented: $model.showingRecoveryPanel) {
      RecoveryPanel(model: model)
        .frame(width: 520, height: 320)
    }
    .sheet(isPresented: $model.showingModelPanel) {
      ModelPanel(model: model)
        .frame(width: 560, height: 560)
    }
    .sheet(isPresented: $model.showingPermissionPanel) {
      PermissionPanel(model: model)
        .frame(width: 520, height: 220)
    }
    .sheet(isPresented: $model.showingOnboarding) {
      FirstRunSetupWizard(model: model)
        .frame(width: 760, height: 620)
    }
    .sheet(isPresented: $model.showingDiagnosticsPanel) {
      DiagnosticsPanel(model: model)
        .frame(width: 900, height: 640)
    }
    .alert("Transcription Error", isPresented: $model.showingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
    .sheet(isPresented: $showingRename) {
      if let renameTargetID,
        let session = model.sessions.first(where: { $0.id == renameTargetID })
      {
        RenameSessionSheet(
          model: model,
          sessionID: session.id,
          originalTitle: session.title,
          suggestedTitle: model.generatedTitle,
          onClose: {
            showingRename = false
          }
        )
      }
    }
    .alert("Rename speaker", isPresented: $showingRenameSpeaker) {
      TextField("Display name", text: $renameSpeakerFieldText)
      Button("Save") {
        if let id = renameSpeakerTargetID {
          model.renameSpeaker(speakerID: id, name: renameSpeakerFieldText)
        }
        showingRenameSpeaker = false
      }
      Button("Cancel", role: .cancel) {
        showingRenameSpeaker = false
      }
    } message: {
      Text("Rename this speaker for the current transcript and saved session.")
    }
    .preferredColorScheme(model.appearanceMode.colorScheme)
  }

  private var selectedSession: LectureSession? {
    guard let id = model.selectedSessionID else { return nil }
    return model.sessions.first { $0.id == id }
  }

  private func beginRename(_ session: LectureSession) {
    renameTargetID = session.id
    renameText = session.title
    showingRename = true
  }

  private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.max(minValue, Swift.min(maxValue, value))
  }

  private var appLayout: some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        SessionSidebar(model: model, onBeginRename: beginRename)
          .frame(width: sidebarColumnWidth)

        ColumnResizeHandle(
          onDrag: { delta in
            if sidebarDragStartWidth == nil {
              sidebarDragStartWidth = sidebarColumnWidth
            }
            let start = sidebarDragStartWidth ?? sidebarColumnWidth
            sidebarColumnWidth = clamp(start + delta, min: 220, max: 380)
          },
          onDragEnd: {
            sidebarDragStartWidth = nil
          }
        )

        VStack(spacing: 0) {
          MainWindowHeader(model: model, selectedSession: selectedSession)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

          Divider()

          TranscriptView(
            model: model,
            followTail: $followTail,
            showingNotesPanel: $showingNotesPanel,
            copiedTranscript: $copiedTranscript,
            onRenameSpeaker: { sid in
              renameSpeakerTargetID = sid
              renameSpeakerFieldText =
                model.allSegments.first { $0.speakerID == sid }?.speakerName ?? sid
              showingRenameSpeaker = true
            }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if showingNotesPanel {
          ColumnResizeHandle(
            onDrag: { delta in
              if notesDragStartWidth == nil {
                notesDragStartWidth = notesColumnWidth
              }
              let start = notesDragStartWidth ?? notesColumnWidth
              let maxNotes = min(560, proxy.size.width * 0.45)
              // Handle is on the notes panel’s leading edge: drag right narrows notes.
              notesColumnWidth = clamp(start - delta, min: 300, max: maxNotes)
            },
            onDragEnd: {
              notesDragStartWidth = nil
            }
          )

          NotesPanel(model: model)
            .frame(width: notesColumnWidth)
        }
      }
    }
  }
}
