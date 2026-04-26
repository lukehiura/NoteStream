import SwiftUI

struct SupportSettingsView: View {
  @State private var copied = false

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 10) {
            Text("If NoteStream is useful, you can support development.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
              Button {
                OpenExternalURL.open(SupportLinks.buyMeACoffee)
              } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
              }
              .buttonStyle(.borderedProminent)

              Button {
                copySupportLink()
              } label: {
                Label(
                  copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
              }
              .buttonStyle(.bordered)
            }

            Link(SupportLinks.buyMeACoffeeDisplayText, destination: SupportLinks.buyMeACoffee)
              .font(.caption)

            Link("Source repository", destination: SupportLinks.repository)
              .font(.caption)
          }

          Spacer()

          VStack(spacing: 8) {
            Image("buy-me-a-coffee-qr", bundle: .module)
              .resizable()
              .interpolation(.none)
              .scaledToFit()
              .frame(width: 120, height: 120)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .overlay {
                RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(Color.secondary.opacity(0.18))
              }

            Text("Scan to support")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Divider()

        Text("Support is optional. NoteStream should remain useful without donating.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    } label: {
      Label("Support", systemImage: "heart")
    }
  }

  private func copySupportLink() {
    ClipboardExporter.copyToClipboard(text: SupportLinks.buyMeACoffee.absoluteString)

    copied = true

    Task {
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      await MainActor.run {
        copied = false
      }
    }
  }
}
