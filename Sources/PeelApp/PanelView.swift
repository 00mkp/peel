import AppKit
import PeelAppCore
import SwiftUI

/// Everything in the menu-bar panel: header, then either the main flow or Settings.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    /// Opens the gear menu (owned by StatusController).
    var showGearMenu: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(model.showingSettings ? "Settings" : "peel").font(.headline)
                Spacer()
                if model.showingSettings {
                    Button("Done") { model.showingSettings = false }.help("Done (Esc)")
                } else {
                    Button {
                        model.panelPinned.toggle()
                    } label: {
                        Image(systemName: model.panelPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .help(model.panelPinned ? "Unpin: close when clicking elsewhere" : "Pin: keep open while you drag files in")
                    Button {
                        showGearMenu()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings, updates and more")
                }
            }
            if model.showingSettings {
                ToolsView()
            } else {
                MainView()
                Text("Tip: hold Shift while dragging files anywhere for quick actions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
