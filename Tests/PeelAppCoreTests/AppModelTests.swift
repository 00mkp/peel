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
        #expect(model.validationMessage != nil)
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
}
