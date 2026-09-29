import Foundation
import Testing
@testable import ConvertKit
import TestSupport

/// PDF bookmarks (the outline) survive editing and point at the right pages.
@Suite struct BookmarkTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func book() throws -> URL {
        try Fixtures.makePDFWithBookmarks(at: dir.appendingPathComponent("book.pdf"), pages: 3,
                                          bookmarks: [("Chapter 1", 0), ("Chapter 2", 2)])
    }
    private func out(_ name: String = "out.pdf") -> URL { dir.appendingPathComponent(name) }

    @Test func fixtureHasBookmarks() throws {
        #expect(Fixtures.bookmarks(try book()) == ["Chapter 1@0", "Chapter 2@2"])
    }

    @Test func mergeAddsABookmarkPerFileWithItsOwnBookmarksInside() throws {
        let plain = try Fixtures.makePDF(at: dir.appendingPathComponent("notes.pdf"), pages: 2)
        try PDFBackend.merge([try book(), plain], to: out())
        #expect(Fixtures.bookmarks(out()) == ["book@0", "  Chapter 1@0", "  Chapter 2@2", "notes@3"])
    }

    @Test func splitKeepsBookmarksForKeptPages() throws {
        let outputs = try PDFBackend.split(try book(), ranges: nil) { out("p\($0[0]).pdf") }
        #expect(Fixtures.bookmarks(outputs[2]) == ["Chapter 2@0"])
        #expect(Fixtures.bookmarks(outputs[1]).isEmpty)
    }

    @Test func reorderMovesBookmarksWithTheirPages() throws {
        try PDFBackend.reorder(try book(), order: try PageRange.parse("3,1,2"), to: out())
        #expect(Fixtures.bookmarks(out()) == ["Chapter 1@1", "Chapter 2@0"])
    }

    @Test func deletingABookmarkedPageDropsItsBookmark() throws {
        try PDFBackend.delete(try book(), pages: try PageRange.parse("3"), to: out())
        #expect(Fixtures.bookmarks(out()) == ["Chapter 1@0"])
    }

    @Test func rotateKeepsBookmarks() throws {
        try PDFBackend.rotate(try book(), degrees: 90, pages: nil, to: out())
        #expect(Fixtures.bookmarks(out()) == ["Chapter 1@0", "Chapter 2@2"])
    }
}
