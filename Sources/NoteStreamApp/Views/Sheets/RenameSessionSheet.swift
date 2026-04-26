import NoteStreamCore
import SwiftUI

struct RenameSessionSheet: View {
  @Bindable var model: TranscriptionViewModel

  let sessionID: UUID
  let originalTitle: String
  let suggestedTitle: String?
  let onClose: () -> Void

  @State private var title: String = ""

  private var cleanedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    !cleanedTitle.isEmpty && cleanedTitle != originalTitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Rename Recording")
            .font(.title2.weight(.semibold))

          Text("Use a short name that makes this recording easy to find later.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          onClose()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Close")
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Name")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        TextField("Recording title", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.title3)
          .onSubmit {
            saveIfPossible()
          }

        Text("\(cleanedTitle.count)/72 characters recommended")
          .font(.caption2)
          .foregroundStyle(cleanedTitle.count > 72 ? .orange : .secondary)
      }

      if let suggestedTitle,
        !suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        suggestedTitle != originalTitle
      {
        VStack(alignment: .leading, spacing: 8) {
          Text("AI suggested title")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Button {
            title = suggestedTitle
          } label: {
            HStack {
              Image(systemName: "sparkles")
              Text(suggestedTitle)
                .lineLimit(1)
                .truncationMode(.tail)
              Spacer()
            }
            .padding(10)
            .background(AppSurface.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
          .buttonStyle(.plain)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Current title")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text(originalTitle)
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Spacer()

      HStack {
        Button("Cancel") {
          onClose()
        }

        Spacer()

        Button("Reset") {
          title = originalTitle
        }
        .disabled(title == originalTitle)

        Button("Save") {
          saveIfPossible()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
      }
    }
    .padding(20)
    .frame(width: 520, height: 320)
    .onAppear {
      title = originalTitle
    }
  }

  private func saveIfPossible() {
    guard canSave else { return }

    model.renameSession(id: sessionID, title: cleanedTitle)
    onClose()
  }
}
