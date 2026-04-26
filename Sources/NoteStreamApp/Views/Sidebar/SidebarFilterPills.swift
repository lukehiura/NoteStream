import SwiftUI

struct SidebarFilterPills: View {
  @Binding var selection: SessionFilter

  var body: some View {
    HStack(spacing: 6) {
      filterButton(.all, icon: "tray.full", help: "All")
      filterButton(.completed, icon: "checkmark.circle", help: "Completed")
      filterButton(.partial, icon: "clock", help: "Partial")
      filterButton(.failed, icon: "xmark.circle", help: "Failed")
    }
  }

  @ViewBuilder
  private func filterButton(_ value: SessionFilter, icon: String, help: String) -> some View {
    let isSelected = selection == value
    Button {
      selection = value
    } label: {
      Image(systemName: icon)
        .imageScale(.small)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
          isSelected ? Color.accentColor.opacity(0.18) : AppSurface.subtleFill
        )
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }
}
