import AppKit
import ConvertKit
import PeelAppCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel(stateFile: PeelSupport.appState())
    @MainActor private(set) var status: StatusController!
    @MainActor private(set) var wheel: WheelController!
    private var pendingURLs: [URL] = []
    private var showPanelAtLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.status = StatusController(model: self.model) { [unowned self] in
                AnyView(PanelView().environmentObject(self.model))
            }
            self.wheel = WheelController(model: self.model, status: self.status)
            self.wheel.start()
            self.wheel.previewIfRequested()
            Notifier.shared.onOpen = { [weak self] in self?.status.show() }
            Notifier.shared.activate()
            if let previous = self.model.updatedFrom {
                Notifier.shared.post("Peel updated: \(previous) → \(PeelVersion.current)") {}
            }
            if !self.pendingURLs.isEmpty || self.showPanelAtLaunch {
                self.model.add(self.pendingURLs)
                self.pendingURLs = []
                self.status.show()
            }
        }
    }

    /// "Open With" / files dropped on Peel in Finder: load them into the panel. `peel://` URLs are
    /// commands from the CLI (`peel app login on|off`, `peel app panel`).
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                switch PeelURLCommand(url: url) {
                case let .login(on)?: self.model.setLaunchAtLogin(on)
                case .panel?: if let status = self.status { status.show() } else { self.showPanelAtLaunch = true }
                case nil: break
                }
            }
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return }
            guard let status = self.status else { self.pendingURLs += files; return }
            self.model.add(files)
            status.show()
        }
    }

    /// Opening Peel again (Finder, Spotlight) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.status?.show() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            self.model.refreshTools()
            self.model.refreshLoginItem()
        }
    }
}

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Peel has no windows of its own; the status item, panel and wheel are AppKit-managed.
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }   // no empty window on ⌘,
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
