import AppKit
import SwiftUI

struct CursorTrackingTextEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var cursorOffset: Int?

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .noBorder

    let textView = NSTextView()
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.font = NSFont.preferredFont(forTextStyle: .body)
    textView.delegate = context.coordinator
    textView.string = text
    textView.backgroundColor = .clear

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }

    if textView.string != text {
      textView.string = text
    }

    textView.delegate = context.coordinator
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, cursorOffset: $cursorOffset)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    @Binding var cursorOffset: Int?

    init(text: Binding<String>, cursorOffset: Binding<Int?>) {
      self._text = text
      self._cursorOffset = cursorOffset
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text = textView.string
      cursorOffset = characterOffset(
        in: textView.string,
        utf16Location: textView.selectedRange().location
      )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      cursorOffset = characterOffset(
        in: textView.string,
        utf16Location: textView.selectedRange().location
      )
    }

    private func characterOffset(in string: String, utf16Location: Int) -> Int {
      let clamped = max(0, min(utf16Location, string.utf16.count))

      var utf16Count = 0
      var characterCount = 0

      for character in string {
        let next = utf16Count + character.utf16.count
        if next > clamped {
          break
        }

        utf16Count = next
        characterCount += 1
      }

      return characterCount
    }
  }
}
