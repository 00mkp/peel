import ConvertKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit

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
