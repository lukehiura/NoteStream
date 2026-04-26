import NoteStreamCore
import SwiftUI

struct TranscriptExportMenu: View {
  @Bindable var model: TranscriptionViewModel

  var body: some View {
    Menu {
      Button("Markdown…") {
        exportMarkdown()
      }

      Button("Plain Text…") {
        exportPlainText()
      }

      Divider()

      Button("SRT Captions…") {
        exportSRT()
      }

      Button("WebVTT Captions…") {
        exportVTT()
      }

      Divider()

      Button("Session JSON…") {
        exportJSON()
      }
    } label: {
      Label("Export", systemImage: "square.and.arrow.down")
    }
    .buttonStyle(.bordered)
    .labelStyle(.titleAndIcon)
    .disabled(model.allSegments.isEmpty)
    .help("Export transcript")
  }

  private var baseFileName: String {
    let raw = model.selectedFileName ?? "transcript"
    return
      raw
      .replacingOccurrences(of: ".", with: "_")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
  }

  private func handle(_ action: () throws -> Void) {
    do {
      try action()
    } catch {
      model.errorMessage = String(describing: error)
      model.showingError = true
    }
  }

  private func exportMarkdown() {
    handle {
      try SavePanelExporter.saveMarkdown(
        model.transcriptMarkdown,
        suggestedFileName: "\(baseFileName).md"
      )
    }
  }

  private func exportPlainText() {
    handle {
      try SavePanelExporter.saveText(
        model.transcriptPlainText,
        suggestedFileName: "\(baseFileName).txt"
      )
    }
  }

  private func exportSRT() {
    handle {
      let srt = TranscriptSRTFormatter.srt(from: model.allSegments)
      try SavePanelExporter.saveSRT(srt, suggestedFileName: "\(baseFileName).srt")
    }
  }

  private func exportVTT() {
    handle {
      let vtt = TranscriptVTTFormatter.vtt(from: model.allSegments)
      try SavePanelExporter.saveVTT(vtt, suggestedFileName: "\(baseFileName).vtt")
    }
  }

  private func exportJSON() {
    handle {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601

      let payload = ExportedTranscript(
        title: model.selectedFileName ?? "Transcript",
        segments: model.allSegments,
        notesMarkdown: model.notesMarkdown
      )

      let data = try encoder.encode(payload)

      try SavePanelExporter.saveJSON(
        data,
        suggestedFileName: "\(baseFileName).json"
      )
    }
  }
}
