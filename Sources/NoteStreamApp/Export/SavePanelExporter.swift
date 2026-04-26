import AppKit
import Foundation
import UniformTypeIdentifiers

enum SavePanelExporter {
  static func saveMarkdown(_ markdown: String, suggestedFileName: String) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = markdown.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to encode Markdown as UTF-8."
        ])
    }
    try data.write(to: url, options: .atomic)
  }

  static func saveText(_ text: String, suggestedFileName: String) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType.plainText]
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = text.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to encode text as UTF-8."
        ])
    }
    try data.write(to: url, options: .atomic)
  }

  static func saveJSON(_ data: Data, suggestedFileName: String) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType.json]
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK, let url = panel.url else { return }
    try data.write(to: url, options: .atomic)
  }

  static func saveSRT(_ text: String, suggestedFileName: String) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = text.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 6,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to encode SRT as UTF-8."
        ])
    }
    try data.write(to: url, options: .atomic)
  }

  static func saveVTT(_ text: String, suggestedFileName: String) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType(filenameExtension: "vtt") ?? .plainText]
    panel.nameFieldStringValue = suggestedFileName

    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = text.data(using: .utf8) else {
      throw NSError(
        domain: "NoteStream", code: 7,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to encode VTT as UTF-8."
        ])
    }

    try data.write(to: url, options: .atomic)
  }
}
