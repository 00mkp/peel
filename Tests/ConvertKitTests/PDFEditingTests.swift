import Foundation
import PDFKit
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct PDFEditingTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func pdf(_ name: String = "doc.pdf", pages: Int = 3, labels: [String]? = nil) throws -> URL {
        try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: pages, labels: labels)
    }
    private func out(_ name: String = "out.pdf") -> URL { dir.appendingPathComponent(name) }

    @Test func mergeKeepsOrderAndContent() throws {
        let a = try pdf("a.pdf", pages: 2, labels: ["A1", "A2"])
        let b = try pdf("b.pdf", pages: 3, labels: ["B1", "B2", "B3"])
        try PDFBackend.merge([a, b], to: out())
        #expect(Fixtures.pageTexts(out()) == ["A1", "A2", "B1", "B2", "B3"])
    }

    @Test func mergeNeedsTwoFiles() throws {
        let a = try pdf()
        #expect(throws: PeelError.self) { try PDFBackend.merge([a], to: out()) }
    }

    @Test func splitEveryPage() throws {
        let source = try pdf()
        let outputs = try PDFBackend.split(source, ranges: nil) { group in
            out("s-\(PDFBackend.pageLabel(for: group)).pdf")
        }
        #expect(outputs.map(\.lastPathComponent) == ["s-p1.pdf", "s-p2.pdf", "s-p3.pdf"])
        #expect(Fixtures.pageTexts(outputs[2]) == ["Page 3"])
    }

    @Test func splitByRanges() throws {
        let source = try pdf()
        let outputs = try PDFBackend.split(source, ranges: try PageRange.parse("1-2,3")) { group in
            out("s-\(PDFBackend.pageLabel(for: group)).pdf")
        }
        #expect(outputs.map(\.lastPathComponent) == ["s-p1-2.pdf", "s-p3.pdf"])
        #expect(Fixtures.pageTexts(outputs[0]) == ["Page 1", "Page 2"])
    }

    @Test func extractPages() throws {
        try PDFBackend.extract(try pdf(), pages: try PageRange.parse("2-3"), to: out())
        #expect(Fixtures.pageTexts(out()) == ["Page 2", "Page 3"])
    }

    @Test func deletePages() throws {
        try PDFBackend.delete(try pdf(), pages: try PageRange.parse("2"), to: out())
        #expect(Fixtures.pageTexts(out()) == ["Page 1", "Page 3"])
    }

    @Test func deletingEveryPageFails() throws {
        let source = try pdf()
        #expect(throws: PeelError.self) { try PDFBackend.delete(source, pages: try PageRange.parse("1-"), to: out()) }
    }

    @Test func rotateSelectedPagesLeavesInputAlone() throws {
        let source = try pdf(pages: 2)
        try PDFBackend.rotate(source, degrees: 90, pages: try PageRange.parse("1"), to: out())
        #expect(Fixtures.rotations(out()) == [90, 0])
        #expect(Fixtures.rotations(source) == [0, 0])
    }

    @Test func rotateNegativeMeansCounterClockwise() throws {
        try PDFBackend.rotate(try pdf(pages: 2), degrees: -90, pages: nil, to: out())
        #expect(Fixtures.rotations(out()) == [270, 270])
    }

    @Test func rotateRejectsOddAngles() throws {
        let source = try pdf()
        #expect(throws: PeelError.self) { try PDFBackend.rotate(source, degrees: 45, pages: nil, to: out()) }
    }

    @Test func reorderAndReverse() throws {
        let source = try pdf()
        try PDFBackend.reorder(source, order: try PageRange.parse("3,1,2"), to: out("r1.pdf"))
        #expect(Fixtures.pageTexts(out("r1.pdf")) == ["Page 3", "Page 1", "Page 2"])
        try PDFBackend.reorder(source, order: try PageRange.parse("3-1"), to: out("r2.pdf"))
        #expect(Fixtures.pageTexts(out("r2.pdf")) == ["Page 3", "Page 2", "Page 1"])
    }

    @Test func outOfRangePage() throws {
        let source = try pdf()
        #expect(throws: PeelError.pageOutOfBounds(page: 5, count: 3)) {
            try PDFBackend.extract(source, pages: try PageRange.parse("5"), to: out())
        }
        #expect(!FileManager.default.fileExists(atPath: out().path))
    }

    @Test func rejectsNonPDF() throws {
        let fake = try Fixtures.writeText("not a pdf", to: dir.appendingPathComponent("fake.pdf"))
        #expect(throws: PeelError.unreadableFile(fake)) { try PDFBackend.extract(fake, pages: try PageRange.parse("1"), to: out()) }
    }

    @Test func rejectsPasswordProtected() throws {
        let locked = try Fixtures.makePDF(at: dir.appendingPathComponent("locked.pdf"), pages: 1, password: "secret")
        #expect(throws: PeelError.encryptedPDF(locked)) { try PDFBackend.split(locked, ranges: nil) { _ in out() } }
    }

    @Test func pageLabels() {
        #expect(PDFBackend.pageLabel(for: [3]) == "p3")
        #expect(PDFBackend.pageLabel(for: [1, 2, 3]) == "p1-3")
        #expect(PDFBackend.pageLabel(for: [5, 4]) == "p5-4")
    }

    /// 3-page PDF whose page 1 links to page 3.
    private func pdfWithLink(_ name: String) throws -> URL {
        let url = try Fixtures.makeLinkedPDF(at: dir.appendingPathComponent(name))
        #expect(Fixtures.linkTargets(url) == [[2], [], []])
        return url
    }

    // Checkpoint 2 I1: internal links must follow their pages.
    @Test func mergeKeepsInternalLinks() throws {
        let source = try pdfWithLink("l.pdf")
        try PDFBackend.merge([source, source], to: out())
        #expect(Fixtures.linkTargets(out()) == [[2], [], [], [5], [], []])
    }

    @Test func reorderRetargetsLinks() throws {
        try PDFBackend.reorder(try pdfWithLink("l.pdf"), order: try PageRange.parse("2,3,1"), to: out())
        #expect(Fixtures.linkTargets(out()) == [[], [], [1]])
    }

    @Test func splitDropsLinksToPagesThatAreGone() throws {
        let outputs = try PDFBackend.split(try pdfWithLink("l.pdf"), ranges: nil) { out("s\($0[0]).pdf") }
        #expect(Fixtures.linkTargets(outputs[0]) == [[]])
    }

    // Checkpoint 2 I2: owner-password PDFs that forbid assembly must still rotate (or fail loudly).
    @Test(.enabled(if: Fixtures.hasQPDF))
    func rotateWorksOnPermissionRestrictedPDF() throws {
        let source = try pdf("open.pdf", pages: 1)
        let restricted = dir.appendingPathComponent("restricted.pdf")
        try ProcessRunner.runChecked(Fixtures.qpdf, ["--encrypt", "", "own", "256", "--modify=none", "--",
                                                     source.path, restricted.path])
        try PDFBackend.rotate(restricted, degrees: 90, pages: nil, to: out())
        #expect(Fixtures.rotations(out()) == [90])
    }
}
