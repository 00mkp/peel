import AppKit
import Combine
import PeelAppCore
import SwiftUI

/// The menu-bar icon and its panel. Clicking the icon toggles the panel. (Dropping onto the icon was
/// removed: dragging to the top of the screen brings up Stage Manager; Shift-drag covers that need.)
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var fallback: NSPanel?
    private let model: AppModel
    private let makeContent: () -> AnyView
    private var pinWatch: AnyCancellable?
    private var lastClosed = Date.distantPast
    private var outsideClicks: Any?

    init(model: AppModel, content: @escaping () -> AnyView) {
        self.model = model
        makeContent = content
        super.init()
        let host = NSHostingController(rootView: content())
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        if let button = item.button {
            button.image = PeelIcon.menuBarImage()
            button.target = self                        // VoiceOver / keyboard menu-bar navigation
            button.action = #selector(buttonPressed)
            button.setAccessibilityLabel("Peel")
        }
        pinWatch = model.$panelPinned.sink { [weak self] pinned in
            self?.popover.behavior = pinned ? .applicationDefined : .transient
        }
    }

    @objc private func buttonPressed() { toggle() }

    func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastClosed) > 0.3 {
            // (A transient popover closes itself on the same click that lands on the icon;
            // without this check that click would reopen it straight away.)
            show()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosed = Date()
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    /// A transient popover can stop closing on outside clicks after its content swaps (Settings → Done),
    /// so don't rely on it: any click in another app closes the panel unless it's pinned.
    private func watchOutsideClicks() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.panelPinned else { return }
                self.close()
            }
        }
    }

    /// Shows the panel under the icon, or — when the icon is hidden in the menu-bar overflow —
    /// as a small floating panel.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let button = item.button, iconIsOnScreen(button) {
            fallback?.close()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            watchOutsideClicks()
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
            panel.title = "Peel"
            panel.styleMask = [.titled, .closable, .utilityWindow]
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            if let screen = NSScreen.main {
                panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 420, y: screen.visibleFrame.maxY - 8))
            }
            fallback = panel
        }
        fallback?.makeKeyAndOrderFront(nil)
    }
}
