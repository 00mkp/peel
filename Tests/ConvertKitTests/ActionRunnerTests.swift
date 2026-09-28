import Foundation
import PDFKit
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct ActionRunnerTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func pdf(_ name: String, pages: Int = 3) throws -> URL {
        try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: pages)
    }
    private func names(_ outcomes: [ActionOutcome]) -> [String] {
        outcomes.flatMap { (try? $0.result.get()) ?? [] }.map(\.lastPathComponent)
    }

    @Test func convert() throws {
        let png = try Fixtures.makeImage(at: dir.appendingPathComponent("a.png"), width: 10, height: 10, type: .png)
        #expect(names(ActionRunner().run(.convert(to: .jpg, options: ConvertOptions()), on: [png])) == ["a.jpg"])
    }

    @Test func mergeProducesOneFile() throws {
        let outcomes = ActionRunner().run(.pdfMerge, on: [try pdf("a.pdf", pages: 2), try pdf("b.pdf")])
        #expect(outcomes.count == 1)
        #expect(names(outcomes) == ["a-merged.pdf"])
        #expect(PDFDocument(url: dir.appendingPathComponent("a-merged.pdf"))?.pageCount == 5)
    }

    @Test func mergeNeedsTwo() throws {
        let outcomes = ActionRunner().run(.pdfMerge, on: [try pdf("a.pdf")])
        #expect(throws: PeelError.self) { try outcomes[0].result.get() }
    }

    @Test func pdfEdits() throws {
        let source = try pdf("d.pdf")
        let runner = ActionRunner()
        #expect(names(runner.run(.pdfSplit(ranges: nil), on: [source])) == ["d-p1.pdf", "d-p2.pdf", "d-p3.pdf"])
        #expect(names(runner.run(.pdfExtract(pages: try PageRange.parse("2")), on: [source])) == ["d-extract.pdf"])
        #expect(names(runner.run(.pdfDelete(pages: try PageRange.parse("2")), on: [source])) == ["d-deleted.pdf"])
        #expect(names(runner.run(.pdfRotate(degrees: 90, pages: nil), on: [source])) == ["d-rotated.pdf"])
    }

    // Review Focus 2: overlapping ranges with overwrite on must not overwrite this run's own output.
    @Test func splitWithRepeatedRangesKeepsEveryOutput() throws {
        let outcomes = ActionRunner(planner: OutputPlanner(force: true))
            .run(.pdfSplit(ranges: try PageRange.parse("1-2,1-2")), on: [try pdf("d.pdf")])
        #expect(Set(names(outcomes)).count == 2)
    }

    @Test func extractAndZip() throws {
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Fixtures.writeText("hi", to: folder.appendingPathComponent("a.txt"))
        let runner = ActionRunner()
        #expect(names(runner.run(.zip, on: [folder])) == ["stuff.zip"])
        let extracted = names(runner.run(.extract, on: [dir.appendingPathComponent("stuff.zip")]))
        #expect(extracted == ["stuff 2"])
    }

    @Test func missingToolFailsEveryFileAndWritesNothing() throws {
        let clip = try Fixtures.writeText("x", to: dir.appendingPathComponent("clip.mov"))
        let outcomes = ActionRunner(locator: ToolLocator(searchPaths: [])).run(.mediaGif(fps: 10, width: 100), on: [clip])
        #expect(throws: PeelError.missingTool(name: "ffmpeg", installHint: "brew install ffmpeg")) { try outcomes[0].result.get() }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("clip.gif").path))
    }

    @Test func compressToASizeAlsoNeedsFFprobe() throws {
        let tools = dir.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try Fixtures.makeExecutable(at: tools.appendingPathComponent("ffmpeg"), script: "exit 1")
        let clip = try Fixtures.writeText("x", to: dir.appendingPathComponent("clip.mov"))
        let outcomes = ActionRunner(locator: ToolLocator(searchPaths: [tools.path]))
            .run(.mediaCompress(targetBytes: 1_000_000), on: [clip])
        #expect(throws: PeelError.missingTool(name: "ffprobe", installHint: "brew install ffmpeg")) { try outcomes[0].result.get() }
    }

    @Test func alreadyCancelledRunsNothing() throws {
        let token = CancelToken()
        token.cancel()
        let outcomes = ActionRunner().run(.pdfSplit(ranges: nil), on: [try pdf("d.pdf")], cancel: token)
        #expect(outcomes.allSatisfy { $0.isCancelled })
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("d-p1.pdf").path))
    }

    @Test func missingInput() {
        let outcomes = ActionRunner().run(.pdfSplit(ranges: nil), on: [dir.appendingPathComponent("nope.pdf")])
        #expect(throws: PeelError.fileNotFound(dir.appendingPathComponent("nope.pdf"))) { try outcomes[0].result.get() }
    }

    @Test(.enabled(if: Fixtures.has(.ffmpeg)))
    func mediaGif() throws {
        let clip = dir.appendingPathComponent("clip.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=10", "-c:v", "mpeg4", clip.path,
        ])
        #expect(names(ActionRunner().run(.mediaGif(fps: 5, width: 100), on: [clip])) == ["clip.gif"])
    }

    // Review Focus 3: cancelling mid-encode reports the file as cancelled and leaves nothing behind.
    @Test(.enabled(if: Fixtures.has(.ffmpeg)))
    func cancelDuringEncode() throws {
        let clip = dir.appendingPathComponent("long.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=60:size=1280x720:rate=30", "-c:v", "mpeg4", "-q:v", "10", clip.path,
        ])
        let token = CancelToken()
        let finished = DispatchSemaphore(value: 0)
        var outcomes: [ActionOutcome] = []
        DispatchQueue.global().async {
            outcomes = ActionRunner().run(.mediaCompress(targetBytes: nil), on: [clip], cancel: token)
            finished.signal()
        }
        func partials() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".peel-") }
        }
        let deadline = Date().addingTimeInterval(10)
        while partials().isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        token.cancel()
        #expect(finished.wait(timeout: .now() + 10) == .success)
        #expect(outcomes.first?.isCancelled == true)
        #expect(partials().isEmpty)
    }
}
