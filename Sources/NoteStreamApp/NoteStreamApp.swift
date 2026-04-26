import SwiftUI

@main
struct NoteStreamApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(minWidth: 960, minHeight: 520)
    }
    .windowStyle(.automatic)
    .commands {
      CommandGroup(after: .help) {
        Button("Support NoteStream…") {
          OpenExternalURL.open(SupportLinks.buyMeACoffee)
        }

        Button("Copy Support Link") {
          ClipboardExporter.copyToClipboard(text: SupportLinks.buyMeACoffee.absoluteString)
        }
      }
    }
  }
}
