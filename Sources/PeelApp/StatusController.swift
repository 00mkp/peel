import AppKit
import Combine
import PeelAppCore
import SwiftUI

/// The menu-bar icon and its panel. Files dropped on the icon open the panel with them loaded.
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var fallback: NSPanel?
    private let model: AppModel
    private let makeContent: () -> AnyView
    private var pinWatch: AnyCancellable?
    private var lastClosed = Date.distantPast

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
            let drop = StatusDropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [weak self] in self?.toggle() }
            drop.onDrop = { [weak self] urls in
                self?.model.add(urls)
                self?.show()
            }
            button.addSubview(drop)
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
    }

    /// Shows the panel under the icon, or — when the icon is hidden in the menu-bar overflow —
    /// as a small floating panel.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let button = item.button, iconIsOnScreen(button) {
            fallback?.close()
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

/// Transparent layer over the status button: accepts file drops and passes clicks through.
final class StatusDropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    var onClick: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick() }
    override func rightMouseDown(with event: NSEvent) { onClick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (superview as? NSButton)?.highlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        (superview as? NSButton)?.highlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (superview as? NSButton)?.highlight(false)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
