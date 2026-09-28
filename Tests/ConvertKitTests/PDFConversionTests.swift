import AppKit
import Foundation
import PDFKit
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct PDFConversionTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func pdf(pages: Int = 3) throws -> URL {
        try Fixtures.makePDF(at: dir.appendingPathComponent("doc.pdf"), pages: pages)
    }

    @Test func info() throws {
        let info = try PDFBackend.info(try pdf())
        #expect(info.pageCount == 3)
        #expect(info.pageSize == CGSize(width: 612, height: 792))
        #expect(info.isEncrypted == false)
    }

    @Test func infoReportsEncryption() throws {
        let locked = try Fixtures.makePDF(at: dir.appendingPathComponent("l.pdf"), pages: 1, password: "pw")
        #expect(try PDFBackend.info(locked).isEncrypted)
    }

    @Test func extractsText() throws {
        let out = dir.appendingPathComponent("doc.txt")
        try PDFBackend.text(try pdf(), to: out)
        let text = try String(contentsOf: out, encoding: .utf8)
        #expect(text.contains("Page 1"))
        #expect(text.contains("Page 3"))
    }

    @Test func rendersPNGAtRequestedDPI() throws {
        let outputs = try PDFBackend.toImages(try pdf(), format: .png, dpi: 72) { dir.appendingPathComponent("p\($0).png") }
        #expect(outputs.count == 3)
        let info = try #require(Fixtures.imageInfo(outputs[0]))
        #expect(info.width == 612 && info.height == 792 && info.type == "public.png")
    }

    @Test func rendersJPEGAt150DPI() throws {
        let outputs = try PDFBackend.toImages(try pdf(pages: 1), format: .jpg, dpi: 150) { dir.appendingPathComponent("p\($0).jpg") }
        let info = try #require(Fixtures.imageInfo(outputs[0]))
        #expect(info.width == 1275 && info.height == 1650 && info.type == "public.jpeg")
    }

    @Test func honoursPageRotation() throws {
        let rotated = dir.appendingPathComponent("rotated.pdf")
        try PDFBackend.rotate(try pdf(pages: 1), degrees: 90, pages: nil, to: rotated)
        let outputs = try PDFBackend.toImages(rotated, format: .png, dpi: 72) { dir.appendingPathComponent("r\($0).png") }
        let info = try #require(Fixtures.imageInfo(outputs[0]))
        #expect(info.width == 792 && info.height == 612)
    }

    @Test func textToPDFPaginates() throws {
        let lines = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let txt = try Fixtures.writeText(lines, to: dir.appendingPathComponent("long.txt"))
        let out = dir.appendingPathComponent("long.pdf")
        try PDFBackend.fromText(txt, to: out)
        let pages = Fixtures.pageTexts(out)
        #expect(pages.count >= 2)
        #expect(pages.first?.contains("line 1") == true)
        #expect(pages.last?.contains("line 200") == true)
    }

    @Test func emptyTextMakesOneBlankPage() throws {
        let txt = try Fixtures.writeText("", to: dir.appendingPathComponent("empty.txt"))
        let out = dir.appendingPathComponent("empty.pdf")
        try PDFBackend.fromText(txt, to: out)
        #expect(PDFDocument(url: out)?.pageCount == 1)
    }

    // Review Focus 4: non-UTF-8 text must still convert.
    @Test func latin1TextConverts() throws {
        let txt = dir.appendingPathComponent("latin1.txt")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: txt) // "café" in Latin-1
        let out = dir.appendingPathComponent("latin1.pdf")
        try PDFBackend.fromText(txt, to: out)
        #expect(Fixtures.pageTexts(out).first?.contains("café") == true)
    }

    private func dark(_ url: URL, _ x: Int, _ y: Int) -> Bool {
        guard let p = Fixtures.pixel(url, x: x, y: y) else { return false }
        return p.r < 60 && p.g < 60 && p.b < 60
    }

    @Test func rotatedPageContentIsUpright() throws {
        let rotated = dir.appendingPathComponent("rot.pdf")
        try PDFBackend.rotate(try Fixtures.makeMarkedPDF(at: dir.appendingPathComponent("m.pdf")), degrees: 90, pages: nil, to: rotated)
        let image = try PDFBackend.toImages(rotated, format: .png, dpi: 72) { dir.appendingPathComponent("r\($0).png") }[0]
        #expect(Fixtures.imageInfo(image)?.width == 100)
        #expect(dark(image, 95, 5))   // top-left square turns clockwise to the top-right
        #expect(!dark(image, 5, 5))
    }

    // Checkpoint 2 I3: images show the crop box, as viewers do.
    @Test func rendersOnlyTheCropBox() throws {
        let doc = try #require(PDFDocument(url: try Fixtures.makeMarkedPDF(at: dir.appendingPathComponent("plain.pdf"))))
        let url = dir.appendingPathComponent("c.pdf")
        doc.page(at: 0)?.setBounds(CGRect(x: 0, y: 50, width: 100, height: 50), for: .cropBox)
        #expect(doc.write(to: url))
        let image = try PDFBackend.toImages(url, format: .png, dpi: 72) { dir.appendingPathComponent("c\($0).png") }[0]
        let info = try #require(Fixtures.imageInfo(image))
        #expect(info.width == 100 && info.height == 50)
        #expect(dark(image, 5, 5))
    }

    // Checkpoint 2 I4: annotations (highlights, stamps, filled forms) appear in images.
    @Test func rendersAnnotations() throws {
        let doc = try #require(PDFDocument(url: try Fixtures.makeMarkedPDF(at: dir.appendingPathComponent("plain.pdf"))))
        let url = dir.appendingPathComponent("a.pdf")
        let square = PDFAnnotation(bounds: CGRect(x: 150, y: 0, width: 50, height: 30), forType: .square, withProperties: nil)
        square.color = .black
        square.interiorColor = .black
        doc.page(at: 0)?.addAnnotation(square)
        #expect(doc.write(to: url))
        let image = try PDFBackend.toImages(url, format: .png, dpi: 72) { dir.appendingPathComponent("a\($0).png") }[0]
        #expect(dark(image, 185, 90))
    }
}
