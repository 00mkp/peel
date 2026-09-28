import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

final class FakeUI: QuickActionUI {
    var choice: String?
    var chooseItems: [String] = []
    var notifications: [String] = []
    var alerts: [(message: String, copyable: String?)] = []

    init(choice: String? = nil) { self.choice = choice }
    func choose(prompt: String, items: [String]) -> String? { chooseItems = items; return choice }
    func notify(_ message: String) { notifications.append(message) }
    func alert(_ message: String, copyable: String?) { alerts.append((message, copyable)) }
}

@Suite struct QuickActionHandlerTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func handler(_ ui: FakeUI, locator: ToolLocator = .standard) -> QuickActionHandler {
        QuickActionHandler(ui: ui, runner: ActionRunner(locator: locator), locator: locator)
    }
    private func png(_ name: String = "a.png") throws -> URL {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: 10, height: 10, type: .png)
    }
    private func pdf(_ name: String) throws -> URL { try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: 3) }

    @Test func convertThroughThePicker() throws {
        let ui = FakeUI(choice: "jpg")
        #expect(handler(ui).handle(.convert, files: [try png()]) == 0)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.jpg").path))
        #expect(ui.notifications == ["Converted → a.jpg"])
    }

    @Test func pickerListsUnavailableTargetsLast() throws {
        let ui = FakeUI(choice: nil)
        _ = handler(ui, locator: ToolLocator(searchPaths: [])).handle(.convert, files: [try png()])
        #expect(ui.chooseItems.first == "jpg")
        #expect(ui.chooseItems.contains("webp — needs cwebp"))
        let firstUnavailable = ui.chooseItems.firstIndex { $0.contains("needs") } ?? 0
        #expect(ui.chooseItems[firstUnavailable...].allSatisfy { $0.contains("needs") })
    }

    @Test func choosingAnUnavailableTargetExplainsTheInstall() throws {
        let ui = FakeUI(choice: "webp — needs cwebp")
        #expect(handler(ui, locator: ToolLocator(searchPaths: [])).handle(.convert, files: [try png()]) == 1)
        #expect(ui.alerts.first?.copyable == "brew install webp")
        #expect(ui.alerts.first?.message.contains("https://brew.sh") == true)
    }

    @Test func dismissingThePickerDoesNothing() throws {
        let ui = FakeUI(choice: nil)
        #expect(handler(ui).handle(.convert, files: [try png()]) == 0)
        #expect(ui.alerts.isEmpty && ui.notifications.isEmpty)
    }

    @Test func mixedSelectionWithNoCommonTarget() throws {
        let mp3 = try Fixtures.writeText("x", to: dir.appendingPathComponent("a.mp3"))
        let ui = FakeUI()
        #expect(handler(ui).handle(.convert, files: [try pdf("a.pdf"), mp3]) == 1)
        #expect(ui.alerts.first?.message.contains("can't convert") == true)
    }

    @Test func mergeNeedsTwoPDFs() throws {
        let ui = FakeUI()
        #expect(handler(ui).handle(.merge, files: [try pdf("a.pdf")]) == 1)
        #expect(ui.alerts.first?.message.contains("two or more PDF") == true)
    }

    @Test func mergeTwoPDFs() throws {
        let ui = FakeUI()
        #expect(handler(ui).handle(.merge, files: [try pdf("a.pdf"), try pdf("b.pdf")]) == 0)
        #expect(ui.notifications == ["Merged → a-merged.pdf"])
    }

    @Test func splitPDF() throws {
        let ui = FakeUI()
        #expect(handler(ui).handle(.split, files: [try pdf("a.pdf")]) == 0)
        #expect(ui.notifications == ["Split into 3 files"])
    }

    @Test func extractHereRejectsNonArchives() throws {
        let ui = FakeUI()
        #expect(handler(ui).handle(.extractHere, files: [try png()]) == 1)
        #expect(ui.alerts.first?.message.contains("archives") == true)
    }

    @Test func extractRarWithoutUnarShowsInstallCommand() throws {
        let rar = try Fixtures.writeText("x", to: dir.appendingPathComponent("x.rar"))
        let ui = FakeUI()
        #expect(handler(ui, locator: ToolLocator(searchPaths: [])).handle(.extractHere, files: [rar]) == 1)
        #expect(ui.alerts.first?.copyable == "brew install unar")
    }

    @Test func zipSelection() throws {
        let ui = FakeUI()
        #expect(handler(ui).handle(.zip, files: [try png()]) == 0)
        #expect(ui.notifications == ["Zipped → a.zip"])
    }

    @Test func failuresAreListedInOneDialog() throws {
        let fake = try Fixtures.writeText("not a pdf", to: dir.appendingPathComponent("fake.pdf"))
        let ui = FakeUI()
        #expect(handler(ui).handle(.split, files: [fake]) == 1)
        #expect(ui.alerts.first?.message.contains("fake.pdf: can't read") == true)
    }

    @Test func nothingSelected() {
        let ui = FakeUI()
        #expect(handler(ui).handle(.zip, files: []) == 1)
        #expect(!ui.alerts.isEmpty)
    }

    @Test func logUIRecordsAndAnswers() throws {
        let log = dir.appendingPathComponent("log.txt")
        let ui = LogUI(log: log, choice: "jpg")
        #expect(ui.choose(prompt: "Convert to:", items: ["jpg", "png"]) == "jpg")
        ui.notify("done")
        ui.alert("oops", copyable: "brew install x")
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text == "choose: Convert to: | jpg / png\nnotify: done\nalert: oops | copy: brew install x\n")
    }

    @Test func appleScriptStringsAreEscaped() {
        #expect(OsascriptUI.literal("say \"hi\" \\ bye") == "\"say \\\"hi\\\" \\\\ bye\"")
    }

    @Test func unknownQuickActionIsUsageError() {
        #expect(runPeel(["quick-action", "bogus"]).code == 2)
    }
}
