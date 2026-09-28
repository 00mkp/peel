import Foundation
import Testing
@testable import PeelCLI
import TestSupport

@Suite struct PDFCommandTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func pdf(_ name: String, pages: Int = 3) throws -> String {
        try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: pages).path
    }
    private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

    @Test func mergeWritesNextToFirstInput() throws {
        let result = runPeel(["pdf", "merge", try pdf("a.pdf", pages: 2), try pdf("b.pdf", pages: 3)])
        #expect(result.code == 0)
        #expect(Fixtures.pageTexts(URL(fileURLWithPath: path("a-merged.pdf"))).count == 5)
        #expect(result.stdout.contains("✓"))
    }

    @Test func mergeWithOneFileIsUsageError() throws {
        #expect(runPeel(["pdf", "merge", try pdf("a.pdf")]).code == 2)
    }

    @Test func splitIntoFolder() throws {
        let result = runPeel(["pdf", "split", try pdf("My Doc.pdf"), "--pages", "1-2,3", "-o", path("parts")])
        #expect(result.code == 0)
        #expect(FileManager.default.fileExists(atPath: path("parts/My Doc-p1-2.pdf")))
        #expect(FileManager.default.fileExists(atPath: path("parts/My Doc-p3.pdf")))
    }

    @Test func splitEveryPageByDefault() throws {
        #expect(runPeel(["pdf", "split", try pdf("d.pdf")]).code == 0)
        for n in 1...3 { #expect(FileManager.default.fileExists(atPath: path("d-p\(n).pdf"))) }
    }

    @Test func rotateAcceptsNegativeDegrees() throws {
        #expect(runPeel(["pdf", "rotate", try pdf("d.pdf", pages: 1), "--by", "-90"]).code == 0)
        #expect(Fixtures.rotations(URL(fileURLWithPath: path("d-rotated.pdf"))) == [270])
    }

    @Test func rotateRejectsOddAngleAsUsageError() throws {
        #expect(runPeel(["pdf", "rotate", try pdf("d.pdf"), "--by", "45"]).code == 2)
    }

    @Test func extractOutOfRangeFailsWithMessage() throws {
        let result = runPeel(["pdf", "extract", try pdf("d.pdf"), "--pages", "9"])
        #expect(result.code == 1)
        #expect(result.stderr.contains("out of range"))
    }

    @Test func invalidPageSyntaxIsUsageError() throws {
        #expect(runPeel(["pdf", "extract", try pdf("d.pdf"), "--pages", "abc"]).code == 2)
    }

    @Test func deleteAndReorder() throws {
        let source = try pdf("d.pdf")
        #expect(runPeel(["pdf", "delete", source, "--pages", "2"]).code == 0)
        #expect(Fixtures.pageTexts(URL(fileURLWithPath: path("d-deleted.pdf"))) == ["Page 1", "Page 3"])
        #expect(runPeel(["pdf", "reorder", source, "--order", "3,1,2"]).code == 0)
        #expect(Fixtures.pageTexts(URL(fileURLWithPath: path("d-reordered.pdf"))) == ["Page 3", "Page 1", "Page 2"])
    }

    @Test func textCollisionGetsNumbered() throws {
        let source = try pdf("d.pdf")
        #expect(runPeel(["pdf", "text", source]).code == 0)
        #expect(runPeel(["pdf", "text", source]).code == 0)
        #expect(FileManager.default.fileExists(atPath: path("d.txt")))
        #expect(FileManager.default.fileExists(atPath: path("d 2.txt")))
    }

    @Test func missingFileFails() {
        let result = runPeel(["pdf", "text", path("nope.pdf")])
        #expect(result.code == 1)
        #expect(result.stderr.contains("no such file"))
    }

    @Test func infoPrintsPageCount() throws {
        let result = runPeel(["pdf", "info", try pdf("d.pdf")])
        #expect(result.code == 0)
        #expect(result.out.contains { $0.contains("pages:") && $0.contains("3") })
    }

    // Checkpoint 1 I1: -o naming the second input must not overwrite it, even with --force.
    @Test func mergeNeverOverwritesAnyInput() throws {
        let a = try pdf("a.pdf", pages: 2)
        let b = try pdf("b.pdf", pages: 3)
        #expect(runPeel(["pdf", "merge", a, b, "-o", b, "--force"]).code == 0)
        #expect(Fixtures.pageTexts(URL(fileURLWithPath: b)).count == 3)
        #expect(Fixtures.pageTexts(URL(fileURLWithPath: path("b 2.pdf"))).count == 5)
    }
}
