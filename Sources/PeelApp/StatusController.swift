import AppKit
import PeelAppCore
import SwiftUI

/// The menu-bar icon and its panel. Clicking the icon toggles the panel. (Dropping onto the icon was
/// removed: dragging to the top of the screen brings up Stage Manager; Shift-drag covers that need.)
///
/// peel decides when the panel closes, rather than NSPopover's `.transient` mode: a click in another
/// app or switching away closes it, unless it's pinned. (`.transient` stopped closing on outside clicks
/// after Settings → Done, and it closes on the very click that lands on the icon, which needed a
/// timing workaround to stop that click reopening it.)
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var fallback: NSPanel?
    private let model: AppModel
    private let makeContent: () -> AnyView
    private var outsideClicks: Any?
    private var resignWatch: NSObjectProtocol?
    private var keyMonitor: Any?

    init(model: AppModel, content: @escaping () -> AnyView) {
        self.model = model
        makeContent = content
        super.init()
        let host = NSHostingController(rootView: content())
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        if let button = item.button {
            button.image = PeelIcon.menuBarImage()
            button.target = self                        // VoiceOver / keyboard menu-bar navigation
            button.action = #selector(buttonPressed)
            button.setAccessibilityLabel("peel")
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = event.charactersIgnoringModifiers ?? "", flags = event.modifierFlags, window = event.windowNumber
            let handled = MainActor.assumeIsolated {   // local monitors run on the main thread
                self?.handleKey(key, modifiers: flags, windowNumber: window) ?? false
            }
            return handled ? nil : event
        }
    }

    /// Panel shortcuts (see PanelShortcut). Only while the panel is the key window; a handled key is
    /// consumed so nothing else acts on it too.
    private func handleKey(_ key: String, modifiers: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window = NSApp.window(withWindowNumber: windowNumber),
              window === popover.contentViewController?.view.window || window === fallback,
              let shortcut = PanelShortcut(key: key, modifiers: modifiers,
                                           editingText: window.firstResponder is NSText) else { return false }
        switch shortcut {
        case .chooseFiles:
            model.showingSettings = false
            chooseFiles(into: model)
        case .run:
            if !model.showingSettings { Task { await model.run() } }
        case .clear:
            if !model.showingSettings { model.clear() }
        case .settings:
            model.showingSettings = true
        case .close:
            closePanel()
        case .quit:
            NSApp.terminate(nil)
        case .escape:
            if !model.handleEscape() { closePanel() }
        }
        return true
    }

    private lazy var gearMenu = GearMenu(model: model) { [weak self] in self?.closePanel() }

    func showGearMenu() { gearMenu.show() }

    private func closePanel() {
        close()
        fallback?.close()
    }

    @objc private func buttonPressed() { toggle() }

    func toggle() {
        if popover.isShown { close() } else { show() }
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    func popoverDidShow(_ notification: Notification) {
        stopWatching()
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessPinned() }
        }
        resignWatch = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessPinned() }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopWatching()
    }

    private func stopWatching() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        if let resignWatch { NotificationCenter.default.removeObserver(resignWatch) }
        outsideClicks = nil
        resignWatch = nil
    }

    /// Clicks in peel's own windows (the panel, the wheel, the icon) never reach the global monitor.
    private func closeUnlessPinned() {
        if !model.panelPinned { close() }
    }

    /// Shows the panel under the icon, or — when the icon is hidden in the menu-bar overflow —
    /// as a small floating panel.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let button = item.button, iconIsOnScreen(button) {
            fallback?.close()
            if !popover.isShown { model.panelWillOpen() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } else {
            showFallback()
        }
    }

    private func iconIsOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.isVisible, window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    private func showFallback() {
        if fallback == nil {
            let host = NSHostingController(rootView: makeContent())
            host.sizingOptions = [.preferredContentSize]
            let panel = NSPanel(contentViewController: host)
            panel.title = "peel"
            panel.styleMask = [.titled, .closable, .utilityWindow]
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            if let screen = NSScreen.main {
                panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 420, y: screen.visibleFrame.maxY - 8))
            }
            fallback = panel
        }
        if fallback?.isVisible == false { model.panelWillOpen() }
        fallback?.makeKeyAndOrderFront(nil)
    }
}
