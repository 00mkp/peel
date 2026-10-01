# peel Action Wheel + Menu-Bar-Only App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the standalone window with (1) a Shift-drag action wheel and (2) a pinnable menu-bar panel that accepts drops on its icon and contains Settings.

**Architecture:** Pure logic in `PeelAppCore` (`DragDetector`, `WheelMenu`, `QuickSummary`, `AppModel.runQuick`, `panelPinned`), unit-tested. AppKit shell in `PeelApp` (`StatusController` = NSStatusItem + drop view + NSPopover/fallback panel; `WheelController` = 30 ms sampler + overlay NSPanel with `WheelView`; `Notifier`). The SwiftUI `MenuBarExtra`, `WindowPresenter` and main/settings windows are removed.

**Tech Stack:** Swift 6 toolchain (Swift 5 mode), SwiftUI, AppKit (NSStatusItem, NSPopover, NSPanel, NSPasteboard .drag), UserNotifications, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-29-peel-wheel-design.md`

## Global Constraints
- macOS 13+, `scripts/test.sh` for tests (plain `swift test` runs 0 tests here).
- No Dock icon ever (LSUIElement stays true; no `.regular` activation policy anywhere).
- Wheel: ≤ 6 slots (Zip last) + centre More…; only available one-step actions.
- All runs keep Stage 1–3 guarantees (never overwrite inputs, atomic outputs) — they go through `ActionRunner`.
- Verification must never send keystrokes via System Events; capture only peel's own windows by id.

## Review Focus
1. A drag of non-file content (text, images from a browser) or a plain click-drag must never show the wheel.
2. The wheel must hide after every drag (drop, cancel with Esc, drop elsewhere) — never get stuck on screen.
3. Dropping on a wheel slot while a panel job is running must not start a second job (busy notification).
4. Panel pinning must not leave the popover impossible to close (unpin or click the icon closes it).
5. With the menu-bar icon hidden in the overflow, dropping/Open With must still show the panel (fallback).

---

### Task 1: DragDetector (PeelAppCore)

**Files:** Create `Sources/PeelAppCore/DragDetector.swift`; Test `Tests/PeelAppCoreTests/DragDetectorTests.swift`

**Produces:** `struct DragSample { mouseDown, shift: Bool; dragChangeCount: Int; hasFiles: Bool; location: CGPoint }`, `enum DragEvent: Equatable { showWheel(at: CGPoint), hideWheel }`, `struct DragDetector { mutating func update(_:) -> DragEvent? }`

- [ ] Step 1: failing tests

```swift
import CoreGraphics
import Testing
@testable import PeelAppCore

@Suite struct DragDetectorTests {
    private func s(_ down: Bool, shift: Bool = false, count: Int = 1, files: Bool = true,
                   at point: CGPoint = CGPoint(x: 10, y: 20)) -> DragSample {
        DragSample(mouseDown: down, shift: shift, dragChangeCount: count, hasFiles: files, location: point)
    }

    @Test func shiftDragOfFilesShowsOnceThenHidesOnMouseUp() {
        var d = DragDetector()
        #expect(d.update(s(false, count: 1)) == nil)
        #expect(d.update(s(true, count: 1)) == nil)                          // mouse down, no drag yet
        #expect(d.update(s(true, shift: true, count: 1)) == nil)             // shift but no drag started
        #expect(d.update(s(true, shift: true, count: 2)) == .showWheel(at: CGPoint(x: 10, y: 20)))
        #expect(d.update(s(true, shift: true, count: 2)) == nil)             // only once
        #expect(d.update(s(true, shift: false, count: 2)) == nil)            // releasing Shift keeps it
        #expect(d.update(s(false, count: 2)) == .hideWheel)
        #expect(d.update(s(false, count: 2)) == nil)
    }

    @Test func dragWithoutShiftNeverShows() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, count: 6)) == nil)
        #expect(d.update(s(false, count: 6)) == nil)
    }

    @Test func shiftPressedLateInTheDragStillShows() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, count: 6)) == nil)
        #expect(d.update(s(true, shift: true, count: 6, at: CGPoint(x: 1, y: 2))) == .showWheel(at: CGPoint(x: 1, y: 2)))
    }

    @Test func nonFileDragsAreIgnored() {
        var d = DragDetector()
        _ = d.update(s(true, count: 5))
        #expect(d.update(s(true, shift: true, count: 6, files: false)) == nil)
    }

    @Test func staleDragFromBeforeMouseDownIsIgnored() {
        var d = DragDetector()
        _ = d.update(s(false, count: 9))
        #expect(d.update(s(true, shift: true, count: 9)) == nil)             // pasteboard unchanged since mouse-down
    }

    @Test func eachDragShowsAgain() {
        var d = DragDetector()
        _ = d.update(s(true, count: 1))
        #expect(d.update(s(true, shift: true, count: 2)) != nil)
        #expect(d.update(s(false, count: 2)) == .hideWheel)
        _ = d.update(s(true, count: 2))
        #expect(d.update(s(true, shift: true, count: 3)) != nil)
    }
}
```

- [ ] Step 2: run `scripts/test.sh --filter DragDetectorTests` → FAIL (types missing)
- [ ] Step 3: implement

```swift
import CoreGraphics

/// One reading of the global mouse/keyboard/drag state (all readable without special permission).
public struct DragSample: Equatable, Sendable {
    public var mouseDown: Bool
    public var shift: Bool
    /// `NSPasteboard(name: .drag).changeCount` — changes when any app starts a drag.
    public var dragChangeCount: Int
    public var hasFiles: Bool
    public var location: CGPoint

    public init(mouseDown: Bool, shift: Bool, dragChangeCount: Int, hasFiles: Bool, location: CGPoint) {
        self.mouseDown = mouseDown
        self.shift = shift
        self.dragChangeCount = dragChangeCount
        self.hasFiles = hasFiles
        self.location = location
    }
}

public enum DragEvent: Equatable, Sendable {
    case showWheel(at: CGPoint)
    case hideWheel
}

/// Decides when to show the action wheel: a file drag that started after the mouse went down, with
/// Shift held at some point. Once shown it stays until the mouse is released.
public struct DragDetector: Sendable {
    private var wasDown = false
    private var countAtMouseDown = 0
    private var shown = false

    public init() {}

    public mutating func update(_ sample: DragSample) -> DragEvent? {
        defer { wasDown = sample.mouseDown }
        if sample.mouseDown && !wasDown { countAtMouseDown = sample.dragChangeCount }
        guard sample.mouseDown else {
            if shown {
                shown = false
                return .hideWheel
            }
            return nil
        }
        if !shown && sample.shift && sample.hasFiles && sample.dragChangeCount != countAtMouseDown {
            shown = true
            return .showWheel(at: sample.location)
        }
        return nil
    }
}
```

- [ ] Step 4: tests PASS; Step 5: commit `feat: drag detector for the action wheel`

---

### Task 2: WheelMenu + QuickSummary (PeelAppCore)

**Files:** Create `Sources/PeelAppCore/WheelMenu.swift`; Test `Tests/PeelAppCoreTests/WheelMenuTests.swift`

**Produces:** `struct WheelSlot: Equatable, Identifiable { kind: ActionKind; label: String; systemImage: String; id }`, `enum WheelMenu { static let maxSlots = 6; static func slots(for: [URL], locator: ToolLocator = .standard) -> [WheelSlot]; static func action(for: ActionKind) -> PeelAction? }`, `enum QuickSummary { static func text(for: ActionKind, rows: [ResultRow]) -> String }`

- [ ] Step 1: failing tests

```swift
import ConvertKit
import Foundation
import Testing
@testable import PeelAppCore

@Suite struct WheelMenuTests {
    private func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }
    private func kinds(_ files: [URL], locator: ToolLocator = .standard) -> [ActionKind] {
        WheelMenu.slots(for: files, locator: locator).map(\.kind)
    }

    @Test func pdfs() {
        let found = kinds(urls("a.pdf", "b.pdf"))
        #expect(found.first == .pdfMerge)
        #expect(found.contains(.pdfSplit) && found.contains(.convert(.png)))
        #expect(found.last == .zip)
        #expect(found.count <= WheelMenu.maxSlots)
        #expect(!kinds(urls("a.pdf")).contains(.pdfMerge))
    }

    @Test func imagesSkipTheirOwnFormat() {
        let found = kinds(urls("a.png", "b.png"))
        #expect(found.first == .convert(.jpg))
        #expect(!found.contains(.convert(.png)))
    }

    @Test func video() {
        let found = kinds(urls("a.mov"))
        #expect(Array(found.prefix(3)) == [.mediaCompress, .mediaGif, .mediaAudio])
    }

    @Test func missingToolsAreLeftOut() {
        #expect(kinds(urls("a.mov"), locator: ToolLocator(searchPaths: [])) == [.zip])
    }

    @Test func archivesAndUnknown() {
        #expect(kinds(urls("a.zip")).first == .extract)
        #expect(kinds(urls("a.qqqq")) == [.zip])
    }

    @Test func labelsAreShort() {
        let slots = WheelMenu.slots(for: urls("a.pdf", "b.pdf"))
        #expect(slots.first?.label == "Merge")
        #expect(slots.contains { $0.label == "→ PNG" })
    }

    @Test func oneStepDefaults() {
        #expect(WheelMenu.action(for: .pdfSplit) == .pdfSplit(ranges: nil))
        #expect(WheelMenu.action(for: .mediaAudio) == .mediaAudio(to: .mp3))
        #expect(WheelMenu.action(for: .pdfExtract) == nil)
        #expect(WheelMenu.action(for: .mediaTrim) == nil)
    }
}

@MainActor
@Suite struct QuickSummaryTests {
    @Test func texts() throws {
        let dir = FileManager.default.temporaryDirectory
        let ok = ResultRow(inputName: "a.pdf", outputs: [dir.appendingPathComponent("a-merged.pdf")], message: nil, cancelled: false)
        #expect(QuickSummary.text(for: .pdfMerge, rows: [ok]) == "Merge PDFs → a-merged.pdf")
        let many = ResultRow(inputName: "a.pdf", outputs: [dir.appendingPathComponent("1"), dir.appendingPathComponent("2")],
                             message: nil, cancelled: false)
        #expect(QuickSummary.text(for: .pdfSplit, rows: [many]) == "Split PDF → 2 files")
        let bad = ResultRow(inputName: "b.pdf", outputs: [], message: "can't read b.pdf", cancelled: false)
        #expect(QuickSummary.text(for: .pdfSplit, rows: [ok, bad]) == "Split PDF: 1 of 2 failed — b.pdf: can't read b.pdf")
    }
}
```

Note: this requires a public memberwise-style `ResultRow.init(inputName:outputs:message:cancelled:)` (add it in Step 3).

- [ ] Step 2: run → FAIL
- [ ] Step 3: implement `WheelMenu.swift`

```swift
import ConvertKit
import Foundation

public struct WheelSlot: Equatable, Identifiable, Sendable {
    public let kind: ActionKind
    public let label: String
    public let systemImage: String
    public var id: String { label }
}

/// The action wheel's contents: available one-step actions for the dragged files.
public enum WheelMenu {
    public static let maxSlots = 6

    static let preferredTargets: [FileFormat] = [.jpg, .png, .pdf, .mp4, .mp3, .m4a, .webp, .heic, .gif, .txt, .vtt, .srt]

    public static func slots(for files: [URL], locator: ToolLocator = .standard) -> [WheelSlot] {
        let sources = Set(files.compactMap { FileFormat(url: $0) })
        let kinds = ActionCatalog.entries(for: files, locator: locator)
            .filter { $0.isAvailable && action(for: $0.kind) != nil }
            .map(\.kind)
            .filter { kind in
                if case let .convert(target) = kind { return !(sources.count == 1 && sources.contains(target)) }
                return true
            }
        let ranked = kinds.filter { $0 != .zip }.sorted { rank($0) < rank($1) }
        var chosen = Array(ranked.prefix(maxSlots - 1))
        if kinds.contains(.zip) { chosen.append(.zip) }
        return chosen.map { WheelSlot(kind: $0, label: label($0), systemImage: symbol($0)) }
    }

    /// The default, option-free action for a kind (nil when it needs input, e.g. page numbers).
    public static func action(for kind: ActionKind) -> PeelAction? {
        switch kind {
        case let .convert(target): return .convert(to: target, options: ConvertOptions())
        case .pdfMerge: return .pdfMerge
        case .pdfSplit: return .pdfSplit(ranges: nil)
        case .pdfRotate: return .pdfRotate(degrees: 90, pages: nil)
        case .mediaCompress: return .mediaCompress(targetBytes: nil)
        case .mediaGif: return .mediaGif(fps: 12, width: 480)
        case .mediaAudio: return .mediaAudio(to: .mp3)
        case .extract: return .extract
        case .zip: return .zip
        case .pdfExtract, .pdfDelete, .mediaTrim: return nil
        }
    }

    static func rank(_ kind: ActionKind) -> Int {
        switch kind {
        case .pdfMerge: return 0
        case .extract: return 1
        case .mediaCompress: return 2
        case .mediaGif: return 3
        case .mediaAudio: return 4
        case .pdfSplit: return 5
        case let .convert(target): return 10 + (preferredTargets.firstIndex(of: target) ?? 30)
        case .pdfRotate: return 60
        default: return 90
        }
    }

    static func label(_ kind: ActionKind) -> String {
        switch kind {
        case let .convert(target): return "→ " + target.rawValue.uppercased()
        case .pdfMerge: return "Merge"
        case .pdfSplit: return "Split"
        case .pdfRotate: return "Rotate 90°"
        case .mediaCompress: return "Compress"
        case .mediaGif: return "GIF"
        case .mediaAudio: return "MP3"
        case .extract: return "Extract"
        case .zip: return "Zip"
        default: return kind.title
        }
    }

    static func symbol(_ kind: ActionKind) -> String {
        switch kind {
        case .convert: return "arrow.triangle.2.circlepath"
        case .pdfMerge: return "doc.on.doc"
        case .pdfSplit: return "scissors"
        case .pdfRotate: return "rotate.right"
        case .mediaCompress: return "arrow.down.right.and.arrow.up.left"
        case .mediaGif: return "photo.stack"
        case .mediaAudio: return "waveform"
        case .extract: return "shippingbox"
        case .zip: return "archivebox"
        default: return "circle"
        }
    }
}

/// Notification text for a wheel run.
public enum QuickSummary {
    public static func text(for kind: ActionKind, rows: [ResultRow]) -> String {
        let failed = rows.filter { !$0.succeeded && !$0.cancelled }
        if let first = failed.first {
            return "\(kind.title): \(failed.count) of \(rows.count) failed — \(first.inputName): \(first.message ?? "failed")"
        }
        let outputs = rows.flatMap(\.outputs)
        if outputs.count == 1 { return "\(kind.title) → \(outputs[0].lastPathComponent)" }
        return "\(kind.title) → \(outputs.count) files"
    }
}
```

Add to `ResultRow` in `AppModel.swift`:
```swift
    public init(inputName: String, outputs: [URL], message: String?, cancelled: Bool) {
        self.inputName = inputName
        self.outputs = outputs
        self.message = message
        self.cancelled = cancelled
    }
```

- [ ] Step 4: PASS; Step 5: commit `feat: wheel contents and notification text`

---

### Task 3: AppModel quick runs + panel pin state

**Files:** Modify `Sources/PeelAppCore/AppModel.swift`; Test additions in `Tests/PeelAppCoreTests/AppModelTests.swift`

**Produces:** `@Published var panelPinned = false`; `func runQuick(_ kind: ActionKind, on urls: [URL]) async -> [ResultRow]?` (nil when busy or not one-step); `run()` and `runQuick` share `perform(_ action:)`.

- [ ] Step 1: failing tests (new suite)

```swift
@MainActor
@Suite struct QuickRunTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    @Test func runQuickRunsAndShowsInPanel() async throws {
        let model = AppModel()
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        let b = try Fixtures.makePDF(at: dir.appendingPathComponent("b.pdf"), pages: 1)
        let rows = await model.runQuick(.pdfMerge, on: [a, b])
        #expect(rows?.first?.succeeded == true)
        #expect(model.files == [a, b] && model.selection == .pdfMerge)
        #expect(model.results.count == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a-merged.pdf").path))
    }

    @Test func runQuickRejectsActionsThatNeedInput() async throws {
        let model = AppModel()
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        #expect(await model.runQuick(.pdfExtract, on: [a]) == nil)
    }

    @Test func runQuickIsRefusedWhileBusy() async throws {
        let tools = dir.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try Fixtures.makeExecutable(at: tools.appendingPathComponent("ffmpeg"), script: "exec /bin/sleep 30")
        let clip = try Fixtures.writeText("x", to: dir.appendingPathComponent("clip.mov"))
        let model = AppModel(locator: { ToolLocator(searchPaths: [tools.path]) })
        model.add([clip])
        model.selection = .mediaCompress
        let running = Task { await model.run() }
        while !model.isRunning { await Task.yield() }
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        #expect(await model.runQuick(.pdfSplit, on: [a]) == nil)
        model.cancel()
        await running.value
    }

    @Test func pinStateDefaultsOff() {
        #expect(AppModel().panelPinned == false)
    }
}
```

- [ ] Step 2: run → FAIL
- [ ] Step 3: implement — in `AppModel`: add `@Published public var panelPinned = false`; refactor `run()`:

```swift
    public func run() async {
        guard canRun, let kind = selection, let action = try? options.action(for: kind, files: files) else { return }
        _ = await perform(action)
    }

    /// Runs a wheel action with default options. The files and action show in the panel too.
    /// Returns nil (and does nothing) when a job is already running or the action needs input.
    public func runQuick(_ kind: ActionKind, on urls: [URL]) async -> [ResultRow]? {
        guard !isRunning, let action = WheelMenu.action(for: kind) else { return nil }
        files = []
        add(urls)
        selection = kind
        return await perform(action)
    }

    private func perform(_ action: PeelAction) async -> [ResultRow] {
        let files = self.files
        let runner = ActionRunner(planner: OutputPlanner(force: force), locator: makeLocator())
        let token = CancelToken()
        self.token = token
        isRunning = true
        let outcomes = await Task.detached { runner.run(action, on: files, cancel: token) }.value
        let rows = outcomes.map(ResultRow.init)
        results = rows
        isRunning = false
        self.token = nil
        return rows
    }
```

- [ ] Step 4: PASS (full suite); Step 5: commit `feat: quick runs for the wheel; panel pin state`

---

### Task 4: App shell — status item with drops, pinnable popover, Settings inside

**Files:** Replace `Sources/PeelApp/PeelApp.swift`; Create `Sources/PeelApp/StatusController.swift`, `Sources/PeelApp/PanelView.swift`; Modify `Sources/PeelApp/MainView.swift` (remove compact header; MainView becomes the panel body)

- [ ] Step 1: `StatusController.swift`

```swift
import AppKit
import Combine
import PeelAppCore
import SwiftUI

/// The menu-bar icon and its panel. Files dropped on the icon open the panel with them loaded.
@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var fallback: NSPanel?
    private let model: AppModel
    private let makeContent: () -> AnyView
    private var pinWatch: AnyCancellable?

    init(model: AppModel, content: @escaping () -> AnyView) {
        self.model = model
        makeContent = content
        super.init()
        let host = NSHostingController(rootView: content())
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        if let button = item.button {
            button.image = PeelIcon.menuBarImage()
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

    func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
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
```

- [ ] Step 2: `PanelView.swift` — header (title, pin, gear menu), Settings inline

```swift
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
                Text(showingSettings ? "Settings" : "peel").font(.headline)
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
                        Divider()
                        Button("Quit peel") { NSApp.terminate(nil) }
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
}
```

- [ ] Step 3: `MainView.swift` — remove the `compact` header block (Open Window / gear / LoginToggle) and the `compact` flag's padding: the view becomes the panel body (drop area → files → action → results) with no own padding; drop area uses the compact sizes. Remove `@Environment(\.peelActions)`.

- [ ] Step 4: `PeelApp.swift`

```swift
import AppKit
import PeelAppCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()
    @MainActor private(set) var status: StatusController!
    @MainActor private(set) var wheel: WheelController!
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.status = StatusController(model: self.model) { [unowned self] in
                AnyView(PanelView().environmentObject(self.model))
            }
            self.wheel = WheelController(model: self.model, status: self.status)
            self.wheel.start()
            Notifier.shared.onOpen = { [weak self] in self?.status.show() }
            if !self.pendingURLs.isEmpty {
                self.model.add(self.pendingURLs)
                self.pendingURLs = []
                self.status.show()
            }
        }
    }

    /// "Open With" / files dropped on peel in Finder: load them into the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            guard let status = self.status else { self.pendingURLs += urls; return }
            self.model.add(urls)
            status.show()
        }
    }

    /// Opening peel again (Finder, Spotlight) shows the panel.
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
        // peel has no windows of its own; the status item, panel and wheel are AppKit-managed.
        Settings { EmptyView() }
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
```

(Task 4 builds only once Task 5's `WheelController` and `Notifier` exist — do Tasks 4 and 5 together, committing after Task 5.)

---

### Task 5: Wheel overlay + notifications

**Files:** Create `Sources/PeelApp/WheelController.swift`, `Sources/PeelApp/WheelView.swift`, `Sources/PeelApp/Notifier.swift`

- [ ] Step 1: `Notifier.swift`

```swift
import Foundation
import UserNotifications

/// Posts wheel results as notifications (asks for permission once); clicking one opens the panel.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    var onOpen: () -> Void = {}
    private var asked = false

    func post(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let content = UNMutableNotificationContent()
            content.title = "peel"
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if asked { send(); return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in send() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] Step 2: `WheelView.swift`

```swift
import PeelAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The action wheel: slots in a circle around a central "More…"; each slot is a drop target.
struct WheelView: View {
    let slots: [WheelSlot]
    let onDrop: (WheelSlot?, [URL]) -> Void   // nil slot = More…

    static let size: CGFloat = 280

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: Self.size - 8, height: Self.size - 8)
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(slots.count, 1))
                SlotView(title: slot.label, systemImage: slot.systemImage) { urls in onDrop(slot, urls) }
                    .offset(x: cos(angle) * 96, y: sin(angle) * 96)
            }
            SlotView(title: "More…", systemImage: "ellipsis.circle", size: 76) { urls in onDrop(nil, urls) }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

private struct SlotView: View {
    let title: String
    let systemImage: String
    var size: CGFloat = 70
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
            Text(title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(targeted ? Color.accentColor : Color(nsColor: .windowBackgroundColor).opacity(0.9)))
        .foregroundStyle(targeted ? Color.white : Color.primary)
        .scaleEffect(targeted ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            let lock = NSLock()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { onDrop(urls) }
            return true
        }
    }
}
```

- [ ] Step 3: `WheelController.swift`

```swift
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
                Notifier.shared.post("peel is busy with another job — try again when it finishes.")
                return
            }
            Notifier.shared.post(QuickSummary.text(for: slot.kind, rows: rows))
        }
    }
}
```

- [ ] Step 4: `swift build --product PeelApp` → no errors; `scripts/test.sh` → PASS.
- [ ] Step 5: smoke test: build into a temp `APP_DIR`, launch, confirm activation policy is accessory, no titled windows, status item exists; `open -a <app> file.pdf` shows the panel (popover or fallback) with the file (inspect via System Events / window ids only). Quit.
- [ ] Step 6: commit `feat: menu-bar-only shell with droppable icon, pinnable panel and action wheel`

---

### Task 6: Docs, review, merge, install
- [ ] README "peel.app" section rewritten for: menu-bar icon (click / drop onto it), pin, gear (Settings, Quit), Shift-drag wheel, notifications permission, pasteboard-privacy prompt note.
- [ ] Fresh reviewer (opus) on the branch with the Review Focus list; fix Critical/Important RED→GREEN where testable.
- [ ] Merge to master, `./install.sh`, relaunch; owner tries the wheel by hand.
