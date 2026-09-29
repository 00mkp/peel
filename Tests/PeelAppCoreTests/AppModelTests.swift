import ConvertKit
import Foundation
import Testing
@testable import PeelAppCore
import TestSupport

@MainActor
@Suite struct AppModelTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func png(_ name: String) throws -> URL {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: 10, height: 10, type: .png)
    }
    private func pdf(_ name: String) throws -> URL { try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: 3) }

    @Test func droppingPDFsOffersPDFToolsAndSelectsTheFirst() throws {
        let model = AppModel()
        model.add([try pdf("a.pdf"), try pdf("b.pdf")])
        #expect(model.entries.first?.kind == .pdfMerge)
        #expect(model.selection == .pdfMerge)
        #expect(model.canRun)
    }

    @Test func duplicatesAreIgnoredAndRemovalRecomputes() throws {
        let model = AppModel()
        let a = try pdf("a.pdf")
        let b = try pdf("b.pdf")
        model.add([a, b, a])
        #expect(model.files == [a, b])
        model.remove(b)
        #expect(!model.entries.contains { $0.kind == .pdfMerge })
        #expect(model.selection != .pdfMerge)
        model.clear()
        #expect(model.files.isEmpty && model.entries.isEmpty && model.selection == nil)
    }

    @Test func optionValidation() throws {
        let model = AppModel()
        model.add([try pdf("a.pdf")])
        model.selection = .pdfExtract
        #expect(model.validationMessage == nil)   // nothing typed yet: no error, but Run stays off
        #expect(!model.canRun)
        model.options.pages = "abc"
        #expect(model.validationMessage != nil)
        model.options.pages = "1-2"
        #expect(model.validationMessage == nil)
        model.selection = .convert(.jpg)
        model.options.quality = "150"
        #expect(model.validationMessage == "Quality must be 1–100.")
    }

    @Test func trimValidation() throws {
        var options = ActionOptions()
        options.from = "0:10"
        options.to = "0:05"
        #expect(throws: PeelError.self) { try options.action(for: .mediaTrim, files: []) }
        options.to = "0:20"
        #expect(try options.action(for: .mediaTrim, files: []) == .mediaTrim(from: 10, until: 20))
    }

    @Test func runProducesResults() async throws {
        let model = AppModel()
        model.add([try png("a.png"), try png("b.png")])
        model.selection = .convert(.jpg)
        await model.run()
        #expect(model.results.count == 2)
        #expect(model.results.allSatisfy { $0.succeeded })
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("b.jpg").path))
        #expect(!model.isRunning)
    }

    @Test func failuresShowTheirMessage() async throws {
        let model = AppModel()
        let fake = try Fixtures.writeText("nope", to: dir.appendingPathComponent("fake.pdf"))
        model.add([fake])
        model.selection = .pdfSplit
        await model.run()
        #expect(model.results.first?.message?.contains("can't read") == true)
    }

    @Test func unavailableActionExplainsTheInstall() throws {
        let model = AppModel(locator: { ToolLocator(searchPaths: []) })
        model.add([try png("a.png")])
        model.selection = .convert(.webp)
        #expect(!model.canRun)
        let help = try #require(model.installHelp)
        #expect(help.command == "brew install webp")
        #expect(help.homebrewMissing)
        #expect(model.selection == .convert(.webp))
    }

    @Test func firstSelectionPrefersAvailableActions() throws {
        let model = AppModel(locator: { ToolLocator(searchPaths: []) })
        model.add([try Fixtures.writeText("x", to: dir.appendingPathComponent("a.mov"))])
        #expect(model.selectedEntry?.isAvailable == true)
    }

    // Review Focus 4: installing a tool while the app is open makes it available on re-check.
    @Test func refreshPicksUpANewlyInstalledTool() throws {
        let tools = dir.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let model = AppModel(locator: { ToolLocator(searchPaths: [tools.path]) })
        model.add([try png("a.png")])
        #expect(model.entries.first { $0.kind == .convert(.webp) }?.isAvailable == false)
        try Fixtures.makeExecutable(at: tools.appendingPathComponent("cwebp"), script: "exit 0")
        model.refreshTools()
        #expect(model.entries.first { $0.kind == .convert(.webp) }?.isAvailable == true)
        #expect(model.tools.first { $0.tool == .cwebp }?.path != nil)
    }

    @Test func overwriteToggleNeverReplacesInputs() async throws {
        let model = AppModel()
        let input = try png("a.png")
        let before = try Data(contentsOf: input)
        model.add([input])
        model.force = true
        model.selection = .convert(.png)
        model.options.width = "5"
        await model.run()
        #expect(try Data(contentsOf: input) == before)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a 2.png").path))
    }

    // Final review I2: a value in a field that doesn't apply to the chosen action must not block Run.
    @Test func hiddenFieldsDoNotBlockRun() throws {
        let model = AppModel()
        model.add([try png("a.png")])
        model.selection = .convert(.jpg)
        model.options.quality = "150"
        #expect(model.validationMessage != nil)
        model.selection = .convert(.png)
        #expect(model.validationMessage == nil)
        model.options.dpi = "5"
        #expect(model.validationMessage == nil)  // dpi only applies to PDF input
        #expect(ActionOptions.showsQuality(for: .jpg) && !ActionOptions.showsQuality(for: .png))
    }

    // Final review I1: the file list can't change under a running job (which would hide Cancel).
    @Test func filesAreLockedWhileRunning() async throws {
        let tools = dir.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try Fixtures.makeExecutable(at: tools.appendingPathComponent("ffmpeg"), script: "exec /bin/sleep 30")
        let clip = try Fixtures.writeText("x", to: dir.appendingPathComponent("clip.mov"))
        let model = AppModel(locator: { ToolLocator(searchPaths: [tools.path]) })
        model.add([clip])
        model.selection = .mediaCompress
        let run = Task { await model.run() }
        while !model.isRunning { await Task.yield() }
        try await Task.sleep(nanoseconds: 300_000_000)
        model.clear()
        model.remove(clip)
        model.add([try png("late.png")])
        #expect(model.files == [clip])
        #expect(model.selection == .mediaCompress)
        model.cancel()
        await run.value
        #expect(model.results.first?.cancelled == true)
    }

    // Polish: Trim doesn't complain before anything is typed.
    @Test func emptyRequiredFieldsShowNoErrorButBlockRun() throws {
        let model = AppModel()
        model.add([try Fixtures.writeText("x", to: dir.appendingPathComponent("a.mov"))])
        model.selection = .mediaTrim
        #expect(model.validationMessage == nil)
        #expect(!model.canRun || model.selectedEntry?.isAvailable == false)
        model.options.from = "abc"
        #expect(model.validationMessage != nil)
    }

    // Polish: actions needing a missing tool are grouped separately from available ones.
    @Test func entriesAreGroupedByAvailability() throws {
        let model = AppModel(locator: { ToolLocator(searchPaths: []) })
        model.add([try png("a.png")])
        #expect(model.availableEntries.allSatisfy { $0.isAvailable })
        #expect(model.unavailableEntries.contains { $0.kind == .convert(.webp) })
        #expect(model.availableEntries.count + model.unavailableEntries.count == model.entries.count)
    }

    @Test func typeLabels() throws {
        #expect(AppModel.typeLabel(for: URL(fileURLWithPath: "/tmp/a.HEIC")) == "HEIC")
        #expect(AppModel.typeLabel(for: URL(fileURLWithPath: "/tmp/b.tar.gz")) == "TAR.GZ")
        #expect(AppModel.typeLabel(for: dir) == "Folder")
        #expect(AppModel.typeLabel(for: URL(fileURLWithPath: "/tmp/c.qqqq")) == "QQQQ")
        #expect(AppModel.typeLabel(for: URL(fileURLWithPath: "/tmp/Makefile")) == "File")
    }

    @Test func removingAFileClearsResults() async throws {
        let model = AppModel()
        let a = try png("a.png")
        model.add([a, try png("b.png")])
        model.selection = .convert(.jpg)
        await model.run()
        #expect(!model.results.isEmpty)
        model.remove(a)
        #expect(model.results.isEmpty)
    }

    // Polish: Open at Login toggle.
    @Test func openAtLogin() throws {
        let item = FakeLoginItem()
        let model = AppModel(loginItem: item)
        #expect(!model.launchAtLogin)
        model.setLaunchAtLogin(true)
        #expect(item.enabled && model.launchAtLogin && model.loginItemError == nil)
        item.failure = "not allowed"
        model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin)          // unchanged when the system refuses
        #expect(model.loginItemError?.contains("not allowed") == true)
    }

    @Test func menuBarIconIsATemplateTwist() throws {
        let image = PeelIcon.menuBarImage()
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 18, height: 18))
        #expect(PeelIcon.inkCoverage() > 0.08 && PeelIcon.inkCoverage() < 0.6)
    }
}

final class FakeLoginItem: LoginItem {
    var enabled = false
    var failure: String?
    var approvalNeeded = false
    var isEnabled: Bool { enabled }
    var needsApproval: Bool { approvalNeeded }
    func setEnabled(_ on: Bool) throws {
        if let failure { throw PeelError.invalidArgument(failure) }
        if approvalNeeded { return }
        enabled = on
    }
}

@MainActor
@Suite struct LoginItemTests {
    // Polish review: the toggle follows changes made in System Settings.
    @Test func loginItemIsReReadOnActivation() {
        let item = FakeLoginItem()
        let model = AppModel(loginItem: item)
        item.enabled = true
        model.refreshLoginItem()
        #expect(model.launchAtLogin)
    }

    // Polish review: macOS wants approval → say so instead of silently snapping back to off.
    @Test func loginItemNeedingApprovalExplainsWhy() {
        let item = FakeLoginItem()
        item.approvalNeeded = true
        let model = AppModel(loginItem: item)
        model.setLaunchAtLogin(true)
        #expect(!model.launchAtLogin)
        #expect(model.loginItemNeedsApproval)
        #expect(model.loginItemError?.contains("Login Items") == true)
    }
}

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

    // Review: the wheel uses default options — never the panel's Overwrite setting.
    @Test func runQuickNeverOverwrites() async throws {
        let model = AppModel()
        model.force = true
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        let b = try Fixtures.makePDF(at: dir.appendingPathComponent("b.pdf"), pages: 1)
        let existing = try Fixtures.writeText("keep", to: dir.appendingPathComponent("a-merged.pdf"))
        _ = await model.runQuick(.pdfMerge, on: [a, b])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a-merged 2.pdf").path))
    }

    @Test func runQuickResetsOptionsAndReplacesFiles() async throws {
        let model = AppModel()
        let old = try Fixtures.makePDF(at: dir.appendingPathComponent("old.pdf"), pages: 1)
        model.add([old])
        model.options.degrees = 180
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        _ = await model.runQuick(.pdfRotate, on: [a])
        #expect(model.files == [a])
        #expect(model.options.degrees == 90)
    }

    @Test func pinStateDefaultsOff() {
        #expect(AppModel().panelPinned == false)
    }
}
