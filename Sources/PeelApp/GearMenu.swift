import AppKit
import PeelAppCore

/// The panel's gear menu. A plain NSMenu (like mutewake's) rather than a SwiftUI Menu: SwiftUI drops a
/// ⌘Q it thinks clashes with the app's own Quit, and NSMenu shows every shortcut and icon as given.
/// The shortcuts themselves are handled by StatusController while the panel is open.
@MainActor
final class GearMenu: NSObject {
    private let model: AppModel
    private let closePanel: () -> Void

    init(model: AppModel, closePanel: @escaping () -> Void) {
        self.model = model
        self.closePanel = closePanel
    }

    /// Pops the menu up under the mouse (the gear button was just clicked).
    func show() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Settings…", "gearshape", key: ",", #selector(settings)))
        menu.addItem(item("About peel", "info.circle", #selector(about)))
        menu.addItem(item("Check for Updates…", "arrow.down.circle", #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("Uninstall peel…", "trash", #selector(uninstall)))
        menu.addItem(item("Quit peel", "power", key: "q", #selector(quit)))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func item(_ title: String, _ symbol: String, key: String = "", _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func settings() { model.showingSettings = true }
    @objc private func quit() { NSApp.terminate(nil) }

    // These open their own window or alert: close the panel first so it isn't left on top.
    @objc private func about() { dismissThen(LifecycleActions.about) }
    @objc private func checkForUpdates() { dismissThen(LifecycleActions.checkForUpdates) }
    @objc private func uninstall() { dismissThen(LifecycleActions.uninstall) }

    private func dismissThen(_ action: @escaping @MainActor () -> Void) {
        closePanel()
        DispatchQueue.main.async { action() }
    }
}
