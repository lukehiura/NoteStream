import AppKit
import Foundation
import NoteStreamCore
import NoteStreamInfrastructure
import SwiftUI
import UniformTypeIdentifiers

struct SettingsPanel: View {
  @Bindable var model: TranscriptionViewModel
  @State private var selectedSection: SettingsSection = .aiNotes

  var body: some View {
    HSplitView {
      List(SettingsSection.allCases, selection: $selectedSection) { section in
        Label(section.title, systemImage: section.icon)
          .tag(section)
      }
      .listStyle(.sidebar)
      .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack {
            Label(selectedSection.title, systemImage: selectedSection.icon)
              .font(.title2.weight(.semibold))

            Spacer()

            Button("Close") {
              model.showingSettingsPanel = false
            }
            .keyboardShortcut(.defaultAction)
          }

          switch selectedSection {
          case .general:
            GeneralSettingsView(model: model)
          case .transcription:
            TranscriptionSettingsView(model: model)
          case .speakers:
            SpeakerSettingsView(model: model)
          case .aiNotes:
            AINotesSettingsView(model: model)
          case .appearance:
            AppearanceSettingsView(model: model)
          }
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
      }
      .frame(minWidth: 620)
    }
    .onAppear {
      selectedSection = SettingsSection(rawValue: model.preferredSettingsSectionRaw) ?? .aiNotes
      if model.llmProvider == .ollama {
        model.refreshAvailableLocalLLMModels()
      }
    }
    .onChange(of: selectedSection) { _, newSection in
      model.preferredSettingsSectionRaw = newSection.rawValue
      if newSection == .aiNotes, model.llmProvider == .ollama {
        model.refreshAvailableLocalLLMModels()
      }
    }
  }
}
