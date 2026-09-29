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
