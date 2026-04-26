import AppKit

enum ClipboardExporter {
  static func copyToClipboard(text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }
}
