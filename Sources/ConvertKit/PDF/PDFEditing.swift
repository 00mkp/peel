import Foundation
import PDFKit

/// PDF operations built on PDFKit. Every operation writes a new file; inputs are never modified.
public enum PDFBackend {
    /// Opens a PDF, rejecting unreadable and password-protected files.
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw PeelError.unreadableFile(url) }
        if doc.isLocked { throw PeelError.encryptedPDF(url) }
        return doc
    }

    static func save(_ doc: PDFDocument, to url: URL) throws {
        try AtomicOutput.write(to: url) { temp in
            guard doc.write(to: temp) else { throw PeelError.writeFailed(url) }
        }
    }

    /// A new document made of 1-based `pages` of `source` (repeats allowed).
    /// `source` must stay alive until the result is written, or copied pages can render blank.
    static func document(from source: PDFDocument, pages: [Int]) -> PDFDocument {
        let result = PDFDocument()
        for number in pages {
            if let page = source.page(at: number - 1)?.copy() as? PDFPage {
                result.insert(page, at: result.pageCount)
            }
        }
        return result
    }

    /// "p3" for one page, "p1-3" / "p5-4" for a run.
    public static func pageLabel(for group: [Int]) -> String {
        guard let first = group.first, let last = group.last else { return "p" }
        return first == last ? "p\(first)" : "p\(first)-\(last)"
    }

    public static func merge(_ inputs: [URL], to output: URL) throws {
        guard inputs.count >= 2 else { throw PeelError.invalidArgument("merge needs at least 2 PDFs") }
        let sources = try inputs.map { try Self.open($0) }
        let result = PDFDocument()
        for source in sources {
            for index in 0..<source.pageCount {
                if let page = source.page(at: index)?.copy() as? PDFPage {
                    result.insert(page, at: result.pageCount)
                }
            }
        }
        try withExtendedLifetime(sources) { try save(result, to: output) }
    }

    /// One file per group. `ranges == nil` → one file per page. `output` names each file.
    public static func split(_ input: URL, ranges: PageRange?, output: (_ group: [Int]) -> URL) throws -> [URL] {
        let doc = try open(input)
        guard doc.pageCount > 0 else { throw PeelError.invalidArgument("\(input.lastPathComponent) has no pages") }
        let groups = try ranges?.groups(count: doc.pageCount) ?? (1...doc.pageCount).map { [$0] }
        var written: [URL] = []
        for group in groups {
            let url = output(group)
            try withExtendedLifetime(doc) { try save(document(from: doc, pages: group), to: url) }
            written.append(url)
        }
        return written
    }

    public static func extract(_ input: URL, pages: PageRange, to output: URL) throws {
        let doc = try open(input)
        let selected = try pages.pages(count: doc.pageCount)
        try withExtendedLifetime(doc) { try save(document(from: doc, pages: selected), to: output) }
    }

    /// Same as extract: pages left out are dropped, repeats duplicate.
    public static func reorder(_ input: URL, order: PageRange, to output: URL) throws {
        try extract(input, pages: order, to: output)
    }

    public static func delete(_ input: URL, pages: PageRange, to output: URL) throws {
        let doc = try open(input)
        let removed = Set(try pages.pages(count: doc.pageCount))
        let kept = (1...max(doc.pageCount, 1)).filter { !removed.contains($0) && $0 <= doc.pageCount }
        guard !kept.isEmpty else { throw PeelError.invalidArgument("can't delete every page") }
        try withExtendedLifetime(doc) { try save(document(from: doc, pages: kept), to: output) }
    }

    /// Rotates clockwise by 90/180/270 (-90 accepted as 270). `pages == nil` → every page.
    public static func rotate(_ input: URL, degrees: Int, pages: PageRange?, to output: URL) throws {
        let normalized = ((degrees % 360) + 360) % 360
        guard [90, 180, 270].contains(normalized) else {
            throw PeelError.invalidArgument("rotation must be 90, 180, 270 or -90")
        }
        let doc = try open(input)
        let targets = Set(try pages?.pages(count: doc.pageCount) ?? Array(0..<doc.pageCount).map { $0 + 1 })
        for index in 0..<doc.pageCount where targets.contains(index + 1) {
            if let page = doc.page(at: index) {
                page.rotation = (page.rotation + normalized) % 360
            }
        }
        try save(doc, to: output)
    }
}
