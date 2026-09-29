import ConvertKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum FixtureError: Error {
    case cannotCreate(URL)
}

/// Runtime generators for test inputs. Nothing binary is committed to the repo.
public enum Fixtures {
    /// A fresh, empty temporary directory, unique per call.
    public static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension Fixtures {
    /// Whether an optional tool is installed (used to skip tests that need it).
    public static func has(_ tool: Tool) -> Bool {
        ToolLocator.standard.find(tool) != nil
    }

    /// Writes an executable shell script (used to fake tools).
    public static func makeExecutable(at url: URL, script: String) throws {
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

extension Fixtures {
    /// Writes a PDF whose page N shows the text "Page N" (or `labels[N-1]`).
    @discardableResult
    public static func makePDF(at url: URL, pages: Int, labels: [String]? = nil,
                               size: CGSize = CGSize(width: 612, height: 792),
                               password: String? = nil) throws -> URL {
        var box = CGRect(origin: .zero, size: size)
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw FixtureError.cannotCreate(url)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
        for index in 0..<pages {
            ctx.beginPDFPage(nil)
            let label = labels?[index] ?? "Page \(index + 1)"
            let text = NSAttributedString(string: label,
                                          attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            ctx.textPosition = CGPoint(x: 72, y: size.height / 2)
            CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// The trimmed text of every page.
    public static func pageTexts(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map {
            (doc.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The /Rotate value of every page.
    public static func rotations(_ url: URL) -> [Int] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { doc.page(at: $0)?.rotation ?? -1 }
    }

    @discardableResult
    public static func writeText(_ text: String, to url: URL) throws -> URL {
        try Data(text.utf8).write(to: url)
        return url
    }
}

extension Fixtures {
    /// Raw pixel size and UTType identifier of an image file, as stored (orientation not applied).
    public static func imageInfo(_ url: URL) -> (width: Int, height: Int, type: String)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height, type as String)
    }
}

extension Fixtures {
    /// Writes a solid orange image. `alpha: true` makes the left half fully transparent.
    /// `orientation` stores an EXIF orientation tag (e.g. 6 = rotate 90° clockwise to display).
    @discardableResult
    public static func makeImage(at url: URL, width: Int, height: Int, type: UTType,
                                 alpha: Bool = false, orientation: Int? = nil,
                                 colorSpace: CFString = CGColorSpace.sRGB) throws -> URL {
        guard let space = CGColorSpace(name: colorSpace),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FixtureError.cannotCreate(url)
        }
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height)) }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw FixtureError.cannotCreate(url)
        }
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotCreate(url) }
        return url
    }

    /// RGBA of one pixel, measured from the top-left corner.
    public static func pixel(_ url: URL, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }
}

extension Fixtures {
    /// One white 200×100 pt page with a 20×20 black square in its top-left corner.
    @discardableResult
    public static func makeMarkedPDF(at url: URL) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw FixtureError.cannotCreate(url) }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 80, width: 20, height: 20))
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    /// Embedded ICC profile name of an image file, if any.
    public static func profileName(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return props[kCGImagePropertyProfileName] as? String
    }

    /// Target page index of every internal link, per page.
    public static func linkTargets(_ url: URL) -> [[Int]] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { index in
            (doc.page(at: index)?.annotations ?? []).filter { $0.type == "Link" }.compactMap { link in
                let destination = link.destination ?? (link.action as? PDFActionGoTo)?.destination
                return destination?.page.map { doc.index(for: $0) }
            }
        }
    }

    /// Hand-written 3-page PDF whose page 1 has a link to page 3.
    /// (PDFKit can't be used to author this: it writes a corrupt page reference for new link destinations.)
    @discardableResult
    public static func makeLinkedPDF(at url: URL) throws -> URL {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [6 0 R] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Type /Annot /Subtype /Link /Rect [72 72 172 92] /Border [0 0 0] /Dest [5 0 R /XYZ 0 792 null] >>",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: url)
        return url
    }

    public static let qpdf = URL(fileURLWithPath: "/opt/homebrew/bin/qpdf")
    public static var hasQPDF: Bool { FileManager.default.isExecutableFile(atPath: qpdf.path) }
}

extension Fixtures {
    /// Hand-written PDF with `pages` pages and top-level bookmarks (label, 0-based page).
    /// (Raw objects: PDFKit doesn't reliably save outlines that a test builds in memory.)
    @discardableResult
    public static func makePDFWithBookmarks(at url: URL, pages: Int, bookmarks: [(String, Int)]) throws -> URL {
        // 1 catalog, 2 pages tree, 3..<3+pages the pages, then the outline root and its items.
        let pageIDs = (0..<pages).map { 3 + $0 }
        let outlineID = 3 + pages
        let itemIDs = bookmarks.indices.map { outlineID + 1 + $0 }
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines \(outlineID) 0 R >>",
            "<< /Type /Pages /Kids [\(pageIDs.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pages) >>",
        ]
        objects += pageIDs.map { _ in "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>" }
        objects.append("<< /Type /Outlines /First \(itemIDs.first ?? 0) 0 R /Last \(itemIDs.last ?? 0) 0 R /Count \(bookmarks.count) >>")
        for (index, (label, page)) in bookmarks.enumerated() {
            var item = "<< /Title (\(label)) /Parent \(outlineID) 0 R /Dest [\(pageIDs[page]) 0 R /XYZ 0 792 null]"
            if index > 0 { item += " /Prev \(itemIDs[index - 1]) 0 R" }
            if index < bookmarks.count - 1 { item += " /Next \(itemIDs[index + 1]) 0 R" }
            objects.append(item + " >>")
        }
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: url)
        return url
    }

    /// Every bookmark as "label@page" (0-based), children indented with "  " per level.
    public static func bookmarks(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url), let root = doc.outlineRoot else { return [] }
        var lines: [String] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let page = destination?.page.map { String(doc.index(for: $0)) } ?? "-"
                lines.append(String(repeating: "  ", count: depth) + "\(child.label ?? "")@\(page)")
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return lines
    }
}

extension Fixtures {
    /// A 16-bit float TIFF in extended-range sRGB (as HDR photo tools write); `alpha` clears the left half.
    @discardableResult
    public static func makeHDRImage(at url: URL, width: Int, height: Int, alpha: Bool = false) throws -> URL {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
                                      space: space, bitmapInfo: info) else { throw FixtureError.cannotCreate(url) }
        context.setFillColor(CGColor(red: 1.3, green: 0.4, blue: 0.1, alpha: 1))   // > 1.0: outside sRGB
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height)) }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            throw FixtureError.cannotCreate(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotCreate(url) }
        return url
    }
}
