import AppKit
import PeelAppCore
import SwiftUI

/// Peel lives in the menu bar. Its windows (main, Settings) are optional and open on demand; the Dock
/// icon shows only while one of them is open.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> AnyView

    init(title: String, content: @escaping () -> AnyView) {
        self.title = title
        makeContent = content
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: makeContent())
            host.sizingOptions = [.preferredContentSize]   // the window follows the content's size
            let window = NSWindow(contentViewController: host)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        // Minimized windows count too: going menu-bar-only would remove their Dock tile.
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.delegate is WindowPresenter
        }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }   // back to menu-bar only
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()
    @MainActor lazy var mainWindow = WindowPresenter(title: "Peel") { [unowned self] in
        AnyView(MainView().environmentObject(self.model).environment(\.peelActions, self.actions).frame(width: 540))
    }
    @MainActor lazy var settingsWindow = WindowPresenter(title: "Peel Settings") { [unowned self] in
        AnyView(ToolsView().environmentObject(self.model).frame(width: 480).padding())
    }
    @MainActor var actions: PeelActions {
        PeelActions(openWindow: { [unowned self] in self.mainWindow.show() },
                    openSettings: { [unowned self] in self.settingsWindow.show() })
    }

    private static let launchedBeforeKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // LSUIElement already starts Peel menu-bar-only. (No setActivationPolicy(.accessory) here:
            // files opened at launch arrive first and have already shown the window with a Dock icon.)
            // First launch ever: show the window once so a fresh install doesn't look like nothing happened.
            if !UserDefaults.standard.bool(forKey: Self.launchedBeforeKey) {
                UserDefaults.standard.set(true, forKey: Self.launchedBeforeKey)
                self.mainWindow.show()
            }
        }
    }

    /// Files dropped on Peel / "Open With": add them and show the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            self.model.add(urls)
            self.mainWindow.show()
        }
    }

    /// Opening Peel again (Finder, Spotlight, Launchpad) while it runs brings up the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.mainWindow.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            self.model.refreshTools()
            self.model.refreshLoginItem()
        }
    }
}

/// App-level actions the views can trigger (open the optional windows).
struct PeelActions {
    var openWindow: () -> Void = {}
    var openSettings: () -> Void = {}
}

private struct PeelActionsKey: EnvironmentKey {
    static let defaultValue = PeelActions()
}

extension EnvironmentValues {
    var peelActions: PeelActions {
        get { self[PeelActionsKey.self] }
        set { self[PeelActionsKey.self] = newValue }
    }
}

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MainView(compact: true)
                .environmentObject(delegate.model)
                .environment(\.peelActions, delegate.actions)
                .frame(width: 380)
        } label: {
            Image(nsImage: PeelIcon.menuBarImage())
        }
        .menuBarExtraStyle(.window)
        .commands {
            // Peel → Settings… (⌘,) while a window is open and the app menu is showing.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.actions.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
