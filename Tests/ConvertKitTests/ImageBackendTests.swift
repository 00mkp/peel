import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ConvertKit
import TestSupport

@Suite struct ImageBackendTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func image(_ name: String, _ width: Int = 400, _ height: Int = 300, type: UTType = .png,
                       alpha: Bool = false, orientation: Int? = nil) throws -> URL {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: width, height: height, type: type,
                               alpha: alpha, orientation: orientation)
    }
    private func out(_ name: String) -> URL { dir.appendingPathComponent(name) }

    @Test func pngToJPEG() throws {
        try ImageBackend.convert(try image("a.png"), to: out("a.jpg"), format: .jpg)
        let info = try #require(Fixtures.imageInfo(out("a.jpg")))
        #expect(info.width == 400 && info.height == 300 && info.type == "public.jpeg")
    }

    @Test func heicToPNG() throws {
        try ImageBackend.convert(try image("a.heic", type: .heic), to: out("a.png"), format: .png)
        #expect(Fixtures.imageInfo(out("a.png"))?.type == "public.png")
    }

    @Test func targetSizeRules() {
        #expect(ImageBackend.targetSize(width: 400, height: 300, options: ImageOptions()) == (400, 300))
        #expect(ImageBackend.targetSize(width: 400, height: 300, options: ImageOptions(width: 200)) == (200, 150))
        #expect(ImageBackend.targetSize(width: 400, height: 300, options: ImageOptions(height: 150)) == (200, 150))
        #expect(ImageBackend.targetSize(width: 400, height: 300, options: ImageOptions(width: 800)) == (400, 300))
        #expect(ImageBackend.targetSize(width: 400, height: 300, options: ImageOptions(width: 800, height: 800)) == (800, 600))
    }

    @Test func resizesOnConvert() throws {
        try ImageBackend.convert(try image("a.png"), to: out("small.png"), format: .png, options: ImageOptions(width: 200))
        let info = try #require(Fixtures.imageInfo(out("small.png")))
        #expect(info.width == 200 && info.height == 150)
    }

    // Review Focus 2: transparency becomes white, not black.
    @Test func transparentAreasBecomeWhiteInJPEG() throws {
        try ImageBackend.convert(try image("t.png", alpha: true), to: out("t.jpg"), format: .jpg)
        let pixel = try #require(Fixtures.pixel(out("t.jpg"), x: 10, y: 150))
        #expect(pixel.r > 240 && pixel.g > 240 && pixel.b > 240)
    }

    @Test func appliesEXIFOrientation() throws {
        try ImageBackend.convert(try image("o.jpg", type: .jpeg, orientation: 6), to: out("o.png"), format: .png)
        let info = try #require(Fixtures.imageInfo(out("o.png")))
        #expect(info.width == 300 && info.height == 400)
    }

    @Test func unreadableImage() throws {
        let bad = try Fixtures.writeText("hello", to: out("bad.jpg"))
        #expect(throws: PeelError.unreadableFile(bad)) { try ImageBackend.convert(bad, to: out("x.png"), format: .png) }
    }

    @Test func missingEncoderFailsFastWithHint() throws {
        let source = try image("a.png")
        #expect(throws: PeelError.missingTool(name: "cwebp", installHint: "brew install webp")) {
            try ImageBackend.convert(source, to: out("a.webp"), format: .webp, locator: ToolLocator(searchPaths: []))
        }
        #expect(!FileManager.default.fileExists(atPath: out("a.webp").path))
    }

    @Test(.enabled(if: Fixtures.has(.cwebp)))
    func webpOutput() throws {
        try ImageBackend.convert(try image("a.png"), to: out("a.webp"), format: .webp, options: ImageOptions(quality: 70))
        #expect(Fixtures.imageInfo(out("a.webp"))?.type == "org.webmproject.webp")
    }

    @Test(.enabled(if: Fixtures.has(.avifenc)))
    func avifOutput() throws {
        try ImageBackend.convert(try image("a.png"), to: out("a.avif"), format: .avif)
        #expect(Fixtures.imageInfo(out("a.avif"))?.width == 400)
    }

    @Test func imagesToPDFOnePagePerImage() throws {
        let a = try image("a.png", 400, 300)
        let b = try image("b.jpg", 300, 400, type: .jpeg)
        try PDFBackend.fromImages([a, b], to: out("both.pdf"))
        let doc = try #require(PDFDocument(url: out("both.pdf")))
        #expect(doc.pageCount == 2)
        #expect(doc.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 400, height: 300))
        #expect(doc.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 300, height: 400))
    }

    // Checkpoint 3 I4: Display P3 (iPhone) colour must survive → WebP.
    @Test(.enabled(if: Fixtures.has(.cwebp)))
    func webpKeepsColorProfile() throws {
        let p3 = try Fixtures.makeImage(at: out("p3.png"), width: 40, height: 30, type: .png, colorSpace: CGColorSpace.displayP3)
        #expect(Fixtures.profileName(p3)?.contains("P3") == true)
        try ImageBackend.convert(p3, to: out("p3.webp"), format: .webp)
        #expect(Fixtures.profileName(out("p3.webp"))?.contains("P3") == true)
    }
}
