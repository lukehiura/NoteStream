import AppKit
import Foundation
import NoteStreamCore
import UniformTypeIdentifiers

enum SavePanelExporter {
  static func saveMarkdown(_ markdown: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      markdown,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
      utf8Context: "Markdown export"
    )
  }

  static func saveText(_ text: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      text,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [.plainText],
      utf8Context: "plain text export"
    )
  }

  static func saveJSON(_ data: Data, suggestedFileName: String) throws {
    try saveData(
      data,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [.json]
    )
  }

  static func saveSRT(_ text: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      text,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText],
      utf8Context: "SRT export"
    )
  }

  static func saveVTT(_ text: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      text,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [UTType(filenameExtension: "vtt") ?? .plainText],
      utf8Context: "WebVTT export"
    )
  }

  private static func saveUTF8Text(
    _ text: String,
    suggestedFileName: String,
    allowedContentTypes: [UTType],
    utf8Context: String
  ) throws {
    guard let data = text.data(using: .utf8) else {
      throw NoteStreamError.utf8EncodingFailed(utf8Context)
    }

    try saveData(
      data,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: allowedContentTypes
    )
  }

  private static func saveData(
    _ data: Data,
    suggestedFileName: String,
    allowedContentTypes: [UTType]
  ) throws {
    guard
      let url = chooseDestination(
        suggestedFileName: suggestedFileName,
        allowedContentTypes: allowedContentTypes
      )
    else {
      return
    }

    try data.write(to: url, options: .atomic)
  }

  private static func chooseDestination(
    suggestedFileName: String,
    allowedContentTypes: [UTType]
  ) -> URL? {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = allowedContentTypes
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK else {
      return nil
    }

    return panel.url
  }
}
