import AppKit
import PeelAppCore
import SwiftUI

/// Everything in the menu-bar panel: header, then either the main flow or Settings.
struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(showingSettings ? "Settings" : "Peel").font(.headline)
                Spacer()
                if showingSettings {
                    Button("Done") { showingSettings = false }
                } else {
                    Button {
                        model.panelPinned.toggle()
                    } label: {
                        Image(systemName: model.panelPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .help(model.panelPinned ? "Unpin: close when clicking elsewhere" : "Pin: keep open while you drag files in")
                    Menu {
                        Button("Settings…") { showingSettings = true }
                        Button("About Peel") { dismissThen(LifecycleActions.about) }
                        Button("Check for Updates…") { dismissThen(LifecycleActions.checkForUpdates) }
                        Divider()
                        Button("Uninstall Peel…") { dismissThen(LifecycleActions.uninstall) }
                        Button("Quit Peel") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if showingSettings {
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
