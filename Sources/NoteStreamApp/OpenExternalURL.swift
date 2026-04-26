import AppKit
import Foundation

enum OpenExternalURL {
  static func open(_ url: URL) {
    NSWorkspace.shared.open(url)
  }
}
