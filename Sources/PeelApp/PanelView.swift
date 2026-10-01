import AppKit
import PeelAppCore
import SwiftUI

/// Everything in the menu-bar panel: header, then either the main flow or Settings.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel

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
                    Menu {
                        // Shortcuts are handled by StatusController; these show them beside the items.
                        Button("Settings…") { model.showingSettings = true }.keyboardShortcut(",")
                        Button("About peel") { dismissThen(LifecycleActions.about) }
                        Button("Check for Updates…") { dismissThen(LifecycleActions.checkForUpdates) }
                        Divider()
                        Button("Uninstall peel…") { dismissThen(LifecycleActions.uninstall) }
                        Button("Quit peel") { NSApp.terminate(nil) }.keyboardShortcut("q")
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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

    /// Closes the panel first, so the About panel or an alert isn't left underneath it.
    private func dismissThen(_ action: @escaping @MainActor () -> Void) {
        (NSApp.delegate as? AppDelegate)?.status.close()
        DispatchQueue.main.async { action() }
    }
}
