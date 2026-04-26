import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsPanel: View {
  @Bindable var model: TranscriptionViewModel

  private var filteredEvents: [DiagnosticsEvent] {
    model.recentDiagnosticsEvents
      .filter { event in
        let levelMatches =
          model.diagnosticsLevelFilter == nil || event.level == model.diagnosticsLevelFilter

        let categoryQuery = model.diagnosticsCategoryFilter.trimmingCharacters(
          in: .whitespacesAndNewlines)
        let categoryMatches =
          categoryQuery.isEmpty
          || event.category.localizedCaseInsensitiveContains(categoryQuery)

        return levelMatches && categoryMatches
      }
      .sorted { $0.timestamp > $1.timestamp }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Diagnostics")
          .font(.title3.weight(.semibold))

        Spacer()

        Button("Refresh") {
          model.refreshDiagnosticsEvents()
        }

        Button("Clear") {
          model.clearDiagnosticsEvents()
        }

        Button("Export Bundle") {
          model.exportDiagnosticsBundle()
        }

        Button("Open Logs Folder") {
          NSWorkspace.shared.open(model.diagnosticsFolderURL)
        }
      }

      HStack {
        Picker("Level", selection: $model.diagnosticsLevelFilter) {
          Text("All").tag(nil as DiagnosticsLevel?)
          Text("Debug").tag(DiagnosticsLevel.debug as DiagnosticsLevel?)
          Text("Info").tag(DiagnosticsLevel.info as DiagnosticsLevel?)
          Text("Warning").tag(DiagnosticsLevel.warning as DiagnosticsLevel?)
          Text("Error").tag(DiagnosticsLevel.error as DiagnosticsLevel?)
        }
        .frame(width: 160)

        TextField("Category filter", text: $model.diagnosticsCategoryFilter)
          .textFieldStyle(.roundedBorder)
      }

      Group {
        Text(
          "Frames: \(model.rollingFrameCount)  Chunks: \(model.rollingChunkCount)  RMS: \(String(format: "%.4f", model.lastRMS))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let err = model.rollingLastError {
          Text("Rolling: \(err)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        Text("App log: \(model.appDiagnosticsPathText)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        if let sessionPath = model.sessionDiagnosticsPathText {
          Text("Session log: \(sessionPath)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }

      List {
        ForEach(filteredEvents) { event in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

              Text(event.level.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(levelColor(event.level))

              Text(event.category)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

              Spacer()
            }

            Text(event.message)
              .font(.callout.weight(.medium))

            if !event.metadata.isEmpty {
              Text(
                event.metadata.sorted { $0.key < $1.key }
                  .map { "\($0.key)=\($0.value)" }
                  .joined(separator: "  ")
              )
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
            }
          }
          .padding(.vertical, 4)
        }
      }

      HStack {
        Button("Copy Summary") {
          ClipboardExporter.copyToClipboard(text: model.diagnosticsSummaryText)
        }

        Spacer()

        Button("Close") { model.showingDiagnosticsPanel = false }
      }
    }
    .padding(16)
    .onAppear {
      model.refreshDiagnosticsEvents()
    }
  }

  private func levelColor(_ level: DiagnosticsLevel) -> Color {
    switch level {
    case .debug: return .secondary
    case .info: return .blue
    case .warning: return .orange
    case .error: return .red
    }
  }
}
