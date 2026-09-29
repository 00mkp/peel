import AppKit
import PeelAppCore
import SwiftUI

/// Watches for a Shift-drag of files anywhere and shows the action wheel at the cursor.
@MainActor
final class WheelController {
    private let model: AppModel
    private let status: StatusController
    private var detector = DragDetector()
    private var timer: Timer?
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var lastTypesCount = -1
    private var lastHasFiles = false

    init(model: AppModel, status: StatusController) {
        self.model = model
        self.status = status
    }

    func start() {
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let pasteboard = NSPasteboard(name: .drag)
        let count = pasteboard.changeCount
        if count != lastTypesCount {           // only look at the types when a new drag began
            lastTypesCount = count
            lastHasFiles = pasteboard.types?.contains(.fileURL) ?? false
        }
        let sample = DragSample(mouseDown: NSEvent.pressedMouseButtons & 1 != 0,
                                shift: NSEvent.modifierFlags.contains(.shift),
                                dragChangeCount: count, hasFiles: lastHasFiles, location: NSEvent.mouseLocation)
        switch detector.update(sample) {
        case let .showWheel(at: point)?:
            let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            show(at: point, files: files)
        case .hideWheel?:
            let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        case nil:
            break
        }
    }

    /// Developer aid: `PEEL_PREVIEW_WHEEL=/a.pdf:/b.pdf` shows the wheel for those files at launch,
    /// centred on screen, so its contents and look can be checked without a real drag.
    func previewIfRequested() {
        guard let list = ProcessInfo.processInfo.environment["PEEL_PREVIEW_WHEEL"], let screen = NSScreen.main else { return }
        let files = list.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        show(at: NSPoint(x: screen.frame.midX, y: screen.frame.midY), files: files)
    }

    private func show(at point: NSPoint, files: [URL]) {
        hideWork?.cancel()
        let view = WheelView(slots: WheelMenu.slots(for: files)) { [weak self] slot, urls in
            self?.handleDrop(slot: slot, urls: urls.isEmpty ? files : urls)
        }
        let size = WheelView.size
        let frame = NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        if panel == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: view)
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    private func handleDrop(slot: WheelSlot?, urls: [URL]) {
        panel?.orderOut(nil)
        guard let slot else {
            if !model.isRunning { model.clear(); model.add(urls) }
            status.show()
            return
        }
        Task { @MainActor in
            guard let rows = await model.runQuick(slot.kind, on: urls) else {
                Notifier.shared.post("Peel is busy with another job — try again when it finishes.")
                return
            }
            Notifier.shared.post(QuickSummary.text(for: slot.kind, rows: rows))
        }
    }
}
