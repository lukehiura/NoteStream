import AppKit
import SwiftUI

struct ColumnResizeHandle: View {
  let onDrag: (CGFloat) -> Void
  let onDragEnd: () -> Void

  @State private var isHovering = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.clear)
        .frame(width: 14)

      RoundedRectangle(cornerRadius: 2)
        .fill(isHovering ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.22))
        .frame(width: isHovering ? 4 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovering = hovering

      if hovering {
        NSCursor.resizeLeftRight.push()
      } else {
        NSCursor.pop()
      }
    }
    .gesture(
      DragGesture(minimumDistance: 1)
        .onChanged { value in
          onDrag(value.translation.width)
        }
        .onEnded { _ in
          onDragEnd()
        }
    )
    .help("Drag to resize column")
  }
}
