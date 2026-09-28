import Foundation
import PDFKit
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct ConverterTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func png(_ name: String) throws -> URL {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: 40, height: 30, type: .png)
    }

    @Test func convertsEachInput() throws {
        let outcomes = Converter().convert([try png("a.png"), try png("b.png")], to: .jpg)
        #expect(outcomes.count == 2)
        #expect(try outcomes[1].result.get().map(\.lastPathComponent) == ["b.jpg"])
    }

    @Test func severalImagesToPDFMakeOneDocument() throws {
        let outcomes = Converter().convert([try png("a.png"), try png("b.png"), try png("c.png")], to: .pdf)
        let outputs = try #require(try outcomes.first?.result.get())
        #expect(outcomes.count == 1)
        #expect(outputs.map(\.lastPathComponent) == ["a.pdf"])
        #expect(PDFDocument(url: outputs[0])?.pageCount == 3)
    }

    @Test func pdfToPNGOneFilePerPage() throws {
        let pdf = try Fixtures.makePDF(at: dir.appendingPathComponent("d.pdf"), pages: 2)
        let outputs = try Converter().convert([pdf], to: .png, options: ConvertOptions(dpi: 36))[0].result.get()
        #expect(outputs.map(\.lastPathComponent) == ["d-p1.png", "d-p2.png"])
    }

    @Test func pdfToTextAndBack() throws {
        let pdf = try Fixtures.makePDF(at: dir.appendingPathComponent("d.pdf"), pages: 1)
        let txt = try Converter().convert([pdf], to: .txt)[0].result.get()[0]
        #expect(txt.lastPathComponent == "d.txt")
        let back = try Converter().convert([txt], to: .pdf)[0].result.get()[0]
        #expect(back.lastPathComponent == "d 2.pdf")
    }

    @Test func subtitles() throws {
        let srt = try Fixtures.writeText("1\n00:00:01,000 --> 00:00:02,000\nHi\n", to: dir.appendingPathComponent("s.srt"))
        #expect(try Converter().convert([srt], to: .vtt)[0].result.get()[0].lastPathComponent == "s.vtt")
    }

    @Test func batchContinuesPastFailures() throws {
        let outcomes = Converter().convert([dir.appendingPathComponent("missing.png"), try png("ok.png")], to: .jpg)
        #expect(throws: PeelError.fileNotFound(dir.appendingPathComponent("missing.png"))) { try outcomes[0].result.get() }
        #expect(try outcomes[1].result.get().count == 1)
    }

    @Test func unknownAndUnsupported() throws {
        let odd = try Fixtures.writeText("?", to: dir.appendingPathComponent("x.qqqq"))
        #expect(throws: PeelError.unknownFormat(odd)) { try Converter().convert([odd], to: .pdf)[0].result.get() }
        let zip = try Fixtures.writeText("?", to: dir.appendingPathComponent("x.zip"))
        #expect(throws: PeelError.unsupportedConversion(from: "zip", to: "pdf")) {
            try Converter().convert([zip], to: .pdf)[0].result.get()
        }
    }

    @Test func batchOutputIsAFolder() throws {
        let outFolder = dir.appendingPathComponent("converted")
        let outcomes = Converter().convert([try png("a.png"), try png("b.png")], to: .jpg, output: outFolder)
        #expect(try outcomes[0].result.get()[0].path == outFolder.appendingPathComponent("a.jpg").path)
    }

    @Test func missingToolReported() throws {
        let converter = Converter(locator: ToolLocator(searchPaths: []))
        #expect(throws: PeelError.missingTool(name: "cwebp", installHint: "brew install webp")) {
            try converter.convert([try png("a.png")], to: .webp)[0].result.get()
        }
    }

    // Checkpoint 3 C1: with --force, one input's output must never replace another input.
    @Test func batchNeverOverwritesAnotherInput() throws {
        let jpg = try Fixtures.makeImage(at: dir.appendingPathComponent("a.jpg"), width: 10, height: 10, type: .jpeg)
        let before = try Data(contentsOf: jpg)
        let outcomes = Converter(planner: OutputPlanner(force: true)).convert([try png("a.png"), jpg], to: .jpg)
        #expect(try Data(contentsOf: jpg) == before)
        #expect(outcomes.allSatisfy { (try? $0.result.get()) != nil })
    }

    // Checkpoint 3 I1: a later file must not overwrite an output made earlier in the same run.
    @Test func batchNeverOverwritesItsOwnEarlierOutput() throws {
        let gif = try Fixtures.makeImage(at: dir.appendingPathComponent("p.gif"), width: 40, height: 30, type: .gif)
        let outputs = Converter(planner: OutputPlanner(force: true)).convert([try png("p.png"), gif], to: .jpg)
            .flatMap { (try? $0.result.get()) ?? [] }
        #expect(Set(outputs.map(\.path)).count == 2)
    }
}
