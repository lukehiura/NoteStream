import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SessionSidebar: View {
  @Bindable var model: TranscriptionViewModel
  let onBeginRename: (LectureSession) -> Void

  @State private var sessionSearch: String = ""
  @State private var sessionFilter: SessionFilter = .all
  @State private var sessionSort: SessionSort = .newest

  private var filteredSessions: [LectureSession] {
    let query = sessionSearch.trimmingCharacters(in: .whitespacesAndNewlines)

    let searched = model.sessions.filter { session in
      guard !query.isEmpty else { return true }

      let combined = [
        session.title,
        session.sourceFileName ?? "",
        session.metadata.transcriptionStatus ?? "",
        session.segments.prefix(8).map(\.text).joined(separator: " "),
      ]
      .joined(separator: " ")

      return combined.localizedCaseInsensitiveContains(query)
    }

    let filtered = searched.filter { session in
      switch sessionFilter {
      case .all:
        return true
      case .completed:
        return session.uiStatus == .completed
      case .partial:
        return session.uiStatus == .partial || session.uiStatus == .empty
      case .failed:
        return session.uiStatus == .failed
      }
    }

    switch sessionSort {
    case .newest:
      return filtered.sorted { $0.createdAt > $1.createdAt }
    case .oldest:
      return filtered.sorted { $0.createdAt < $1.createdAt }
    case .longest:
      return filtered.sorted { $0.transcriptDuration > $1.transcriptDuration }
    case .mostSegments:
      return filtered.sorted { $0.segments.count > $1.segments.count }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      sidebarHeader

      Divider()

      List(selection: $model.selectedSessionID) {
        if filteredSessions.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("No matching sessions")
              .font(.headline)

            Text("Try a different search or filter.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 16)
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        } else {
          ForEach(filteredSessions) { session in
            Button {
              model.loadSession(id: session.id)
            } label: {
              SessionSidebarRow(
                session: session,
                isSelected: model.selectedSessionID == session.id
              )
            }
            .buttonStyle(.plain)
            .tag(session.id)
            .contextMenu {
              Button("Rename") {
                onBeginRename(session)
              }

              Button("Open transcript file") {
                model.openSessionTranscript(id: session.id)
              }

              Button("Reveal in Finder") {
                model.openSessionFolder(id: session.id)
              }

              Divider()

              Button("Delete", role: .destructive) {
                model.deleteSession(id: session.id)
              }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            .listRowSeparator(.hidden)
            .listRowBackground(
              Group {
                if model.selectedSessionID == session.id {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppSurface.selectedFillStrong)
                } else {
                  Color.clear
                }
              }
            )
          }
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
    }
    .background(AppSurface.sidebar)
  }

  private var sidebarHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Library")
          .font(.headline)

        Spacer()

        Button {
          model.startNew()
        } label: {
          Image(systemName: "plus")
        }
        .help("New recording")

        Button {
          Task { await model.reloadSessions() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Reload library")
      }

      TextField("Search transcripts", text: $sessionSearch)
        .textFieldStyle(.roundedBorder)

      SidebarFilterPills(selection: $sessionFilter)

      HStack {
        Text("\(filteredSessions.count) shown")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Menu {
          ForEach(SessionSort.allCases) { sort in
            Button {
              sessionSort = sort
            } label: {
              if sessionSort == sort {
                Label(sort.title, systemImage: "checkmark")
              } else {
                Text(sort.title)
              }
            }
          }
        } label: {
          Label(sessionSort.title, systemImage: "arrow.up.arrow.down")
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
      }
    }
    .padding(12)
  }
}
