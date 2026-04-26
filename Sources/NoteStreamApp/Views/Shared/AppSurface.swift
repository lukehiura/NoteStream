import AppKit
import SwiftUI

enum AppSurface {
  static var window: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var sidebar: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  static var content: Color {
    Color(nsColor: .textBackgroundColor)
  }

  static var panel: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  static var card: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  static var elevatedCard: Color {
    Color(nsColor: .windowBackgroundColor)
  }

  static var separator: Color {
    Color(nsColor: .separatorColor)
  }

  static var subtleFill: Color {
    Color(nsColor: .quaternaryLabelColor).opacity(0.22)
  }

  static var selectedFill: Color {
    Color.accentColor.opacity(0.16)
  }

  static var selectedFillStrong: Color {
    Color.accentColor.opacity(0.24)
  }
}
