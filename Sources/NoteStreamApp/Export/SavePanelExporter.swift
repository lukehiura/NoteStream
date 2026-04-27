import AppKit
import Foundation
import UniformTypeIdentifiers

enum SavePanelExporter {
  static func saveMarkdown(_ markdown: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      markdown,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
      encodingFailureMessage: "Failed to encode Markdown as UTF-8.",
      encodingFailureCode: 3
    )
  }

  static func saveText(_ text: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      text,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [.plainText],
      encodingFailureMessage: "Failed to encode text as UTF-8.",
      encodingFailureCode: 3
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
      encodingFailureMessage: "Failed to encode SRT as UTF-8.",
      encodingFailureCode: 6
    )
  }

  static func saveVTT(_ text: String, suggestedFileName: String) throws {
    try saveUTF8Text(
      text,
      suggestedFileName: suggestedFileName,
      allowedContentTypes: [UTType(filenameExtension: "vtt") ?? .plainText],
      encodingFailureMessage: "Failed to encode VTT as UTF-8.",
      encodingFailureCode: 7
    )
  }

  private static func saveUTF8Text(
    _ text: String,
    suggestedFileName: String,
    allowedContentTypes: [UTType],
    encodingFailureMessage: String,
    encodingFailureCode: Int
  ) throws {
    guard let data = text.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: encodingFailureCode,
        userInfo: [
          NSLocalizedDescriptionKey: encodingFailureMessage
        ])
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
