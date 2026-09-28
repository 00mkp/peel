import CoreGraphics
import CoreText
import Foundation
import PDFKit

public struct PDFInfo: Equatable, Sendable {
    public let pageCount: Int
    public let pageSize: CGSize
    public let title: String?
    public let author: String?
    public let isEncrypted: Bool
}

extension PDFBackend {
    public static func info(_ input: URL) throws -> PDFInfo {
        guard let doc = PDFDocument(url: input) else { throw PeelError.unreadableFile(input) }
        let attributes = doc.documentAttributes ?? [:]
        return PDFInfo(
            pageCount: doc.pageCount,
            pageSize: doc.page(at: 0)?.bounds(for: .mediaBox).size ?? .zero,
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            isEncrypted: doc.isEncrypted)
    }

    /// Plain text of every page, pages separated by a blank line.
    public static func text(_ input: URL, to output: URL) throws {
        let doc = try open(input)
        let pages = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        try TextFile.write(pages.joined(separator: "\n\n"), to: output)
    }

    /// Renders each page to PNG or JPEG. `output` names the file for a 1-based page number.
    public static func toImages(_ input: URL, format: FileFormat, dpi: Int,
                                output: (_ page: Int) -> URL) throws -> [URL] {
        guard format == .png || format == .jpg, let type = format.imageUTType else {
            throw PeelError.unsupportedConversion(from: "pdf", to: format.rawValue)
        }
        let doc = try open(input)
        var written: [URL] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let image = try render(page, dpi: dpi)
            let url = output(index + 1)
            try AtomicOutput.write(to: url) { temp in
                try ImageEncoder.write(image, to: temp, type: type, quality: format == .jpg ? 90 : nil)
            }
            written.append(url)
        }
        return written
    }

    /// Rasterizes what a viewer shows — the crop box, rotated, with annotations — on white at `dpi`.
    static func render(_ page: PDFPage, dpi: Int) throws -> CGImage {
        let box = page.bounds(for: .cropBox)
        let (width, height) = page.rotation % 180 == 0 ? (box.width, box.height) : (box.height, box.width)
        let scale = CGFloat(dpi) / 72
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int((width * scale).rounded()), height: Int((height * scale).rounded()),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PeelError.invalidArgument("page is too large to render at \(dpi) dpi")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else {
            throw PeelError.invalidArgument("page is too large to render at \(dpi) dpi")
        }
        return image
    }

    /// Lays plain text out on US Letter pages (1-inch margins, 10 pt monospace).
    public static func fromText(_ input: URL, to output: URL) throws {
        let text = try TextFile.read(input)
        let font = CTFontCreateUIFontForLanguage(.userFixedPitch, 10, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, 10, nil)
        let attributed = NSAttributedString(string: text,
                                            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        try AtomicOutput.write(to: output) { temp in
            var page = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let context = CGContext(temp as CFURL, mediaBox: &page, nil) else { throw PeelError.writeFailed(output) }
            let path = CGPath(rect: page.insetBy(dx: 72, dy: 72), transform: nil)
            var location = 0
            repeat {
                context.beginPDFPage(nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                CTFrameDraw(frame, context)
                context.endPDFPage()
                let visible = CTFrameGetVisibleStringRange(frame).length
                if visible == 0 { break }
                location += visible
            } while location < attributed.length
            context.closePDF()
        }
    }
}
