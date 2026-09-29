import AppKit
import PeelAppCore
import SwiftUI

/// Receives files dropped on the Dock icon / "Open With", and re-checks tools on activation.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []

    @MainActor var model: AppModel? {
        didSet {
            guard let model, !pending.isEmpty else { return }
            model.add(pending)
            pending = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if let model = self.model { model.add(urls) } else { self.pending += urls }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            self.model?.refreshTools()
            self.model?.refreshLoginItem()
        }
    }
}

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Peel", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(width: 540)
                .onAppear { delegate.model = model }
        }
        // The window grows with its content: just the drop area at first, then files, options, results.
        .windowResizability(.contentSize)
        MenuBarExtra {
            MainView(compact: true)
                .environmentObject(model)
                .frame(width: 380)
                .onAppear { delegate.model = model }
        } label: {
            Image(nsImage: PeelIcon.menuBarImage())
        }
        .menuBarExtraStyle(.window)
        Settings {
            ToolsView()
                .environmentObject(model)
                .frame(width: 480)
                .padding()
        }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
