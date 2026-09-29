import Foundation
import PDFKit

/// PDF operations built on PDFKit. Every operation writes a new file; inputs are never modified.
public enum PDFBackend {
    /// Opens a PDF, rejecting unreadable and password-protected files.
    static func open(_ url: URL) throws -> PDFDocument {
        guard looksLikePDF(url), let doc = PDFDocument(url: url) else { throw PeelError.unreadableFile(url) }
        if doc.isLocked { throw PeelError.encryptedPDF(url) }
        return doc
    }

    /// "%PDF" near the start. Checked before PDFKit so non-PDFs fail quietly (PDFKit logs noise to stderr).
    static func looksLikePDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1024)) ?? Data()
        return head.range(of: Data("%PDF".utf8)) != nil
    }

    static func save(_ doc: PDFDocument, to url: URL) throws {
        try AtomicOutput.write(to: url) { temp in
            guard doc.write(to: temp) else { throw PeelError.writeFailed(url) }
        }
    }

    /// A new document made of 1-based `pages` of `source` (repeats allowed).
    /// `source` must stay alive until the result is written, or copied pages can render blank.
    static func document(from source: PDFDocument, pages: [Int]) -> PDFDocument {
        assemble([(source, pages)])
    }

    /// Copies pages into a new document and re-points internal links at the copies.
    /// Links to pages that weren't copied are removed (they'd otherwise jump to page 1).
    static func assemble(_ parts: [(document: PDFDocument, pages: [Int])]) -> PDFDocument {
        let result = PDFDocument()
        var firstCopy: [ObjectIdentifier: PDFPage] = [:]
        // Each copy with its links' target pages, read from the original: PDFKit resolves destinations
        // lazily, and a copied annotation whose original was never resolved reports no destination.
        var copies: [(page: PDFPage, targets: [PDFDestination?])] = []
        for part in parts {
            for number in part.pages {
                guard let original = part.document.page(at: number - 1) else { continue }
                let targets = original.annotations.map { linkTarget($0) }
                guard let copy = original.copy() as? PDFPage else { continue }
                if firstCopy[ObjectIdentifier(original)] == nil { firstCopy[ObjectIdentifier(original)] = copy }
                result.insert(copy, at: result.pageCount)
                copies.append((copy, targets))
            }
        }
        for (page, targets) in copies {
            for (index, link) in page.annotations.enumerated() where index < targets.count {
                guard let destination = targets[index], let target = destination.page else { continue } // web links etc.
                guard let copy = firstCopy[ObjectIdentifier(target)] else {
                    page.removeAnnotation(link)
                    continue
                }
                // Clear both first: otherwise PDFKit writes the stale /Dest or /A reference.
                link.action = nil
                link.destination = nil
                link.action = PDFActionGoTo(destination: PDFDestination(page: copy, at: destination.point))
            }
        }
        return result
    }

    /// The in-document destination of a link annotation, if it has one.
    private static func linkTarget(_ annotation: PDFAnnotation) -> PDFDestination? {
        guard annotation.type == "Link" else { return nil }
        return annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
    }

    /// "p3" for one page, "p1-3" / "p5-4" for a run.
    public static func pageLabel(for group: [Int]) -> String {
        guard let first = group.first, let last = group.last else { return "p" }
        return first == last ? "p\(first)" : "p\(first)-\(last)"
    }

    public static func merge(_ inputs: [URL], to output: URL) throws {
        guard inputs.count >= 2 else { throw PeelError.invalidArgument("merge needs at least 2 PDFs") }
        let sources = try inputs.map { try Self.open($0) }
        let result = assemble(sources.map { ($0, Array(0..<$0.pageCount).map { $0 + 1 }) })
        try withExtendedLifetime(sources) { try save(result, to: output) }
    }

    /// One file per group. `ranges == nil` → one file per page. `output` names each file.
    /// Stops (removing what it wrote) as soon as `isCancelled` returns true.
    public static func split(_ input: URL, ranges: PageRange?, isCancelled: () -> Bool = { false },
                             output: (_ group: [Int]) -> URL) throws -> [URL] {
        let doc = try open(input)
        guard doc.pageCount > 0 else { throw PeelError.invalidArgument("\(input.lastPathComponent) has no pages") }
        let groups = try ranges?.groups(count: doc.pageCount) ?? (1...doc.pageCount).map { [$0] }
        var written: [URL] = []
        let batch = AtomicBatch()
        do {
            for group in groups {
                if isCancelled() { throw PeelError.cancelled }
                let url = output(group)
                let part = document(from: doc, pages: group)
                try withExtendedLifetime(doc) {
                    try batch.write(to: url) { temp in
                        guard part.write(to: temp) else { throw PeelError.writeFailed(url) }
                    }
                }
                written.append(url)
            }
            try batch.commit()
        } catch {
            batch.discard()
            throw error
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
        let all = Array(0..<doc.pageCount).map { $0 + 1 }
        let targets = Set(try pages?.pages(count: doc.pageCount) ?? all)
        // PDFKit silently ignores rotation on PDFs whose permissions forbid assembly; rotate copies instead.
        // (Editing in place is preferred when allowed: it keeps bookmarks and metadata.)
        let result = doc.allowsDocumentAssembly ? doc : assemble([(doc, all)])
        for index in 0..<result.pageCount where targets.contains(index + 1) {
            if let page = result.page(at: index) {
                page.rotation = (page.rotation + normalized) % 360
            }
        }
        try withExtendedLifetime(doc) { try save(result, to: output) }
    }
}
