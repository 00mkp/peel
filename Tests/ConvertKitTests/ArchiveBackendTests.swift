import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct ArchiveBackendTests {
    let dir: URL
    let folder: URL

    /// dir/My Files/{résumé.txt, sub/b.txt}
    init() throws {
        dir = try Fixtures.tempDir()
        folder = dir.appendingPathComponent("My Files")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Fixtures.writeText("a", to: folder.appendingPathComponent("résumé.txt"))
        try Fixtures.writeText("b", to: folder.appendingPathComponent("sub/b.txt"))
    }

    private func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    // Review Focus 5: spaces/accents survive a zip round trip.
    @Test func zipRoundTrip() throws {
        let zip = dir.appendingPathComponent("bundle.zip")
        try ArchiveBackend.create([folder], at: zip)
        let out = try ArchiveBackend.extract(zip)
        #expect(out.lastPathComponent == "My Files 2")
        #expect(try contents(out.appendingPathComponent("résumé.txt")) == "a")
        #expect(try contents(out.appendingPathComponent("sub/b.txt")) == "b")
    }

    @Test func tarGzRoundTripWithMultipleInputs() throws {
        let extra = try Fixtures.writeText("c", to: dir.appendingPathComponent("c.txt"))
        let tgz = dir.appendingPathComponent("bundle.tar.gz")
        try ArchiveBackend.create([folder, extra], at: tgz)
        let out = try ArchiveBackend.extract(tgz)
        #expect(out.lastPathComponent == "bundle")
        #expect(try contents(out.appendingPathComponent("c.txt")) == "c")
        #expect(try contents(out.appendingPathComponent("My Files/sub/b.txt")) == "b")
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("._c.txt").path))
    }

    @Test func extractingTwiceNumbersTheFolder() throws {
        let zip = dir.appendingPathComponent("bundle.zip")
        try ArchiveBackend.create([folder], at: zip)
        _ = try ArchiveBackend.extract(zip)
        #expect(try ArchiveBackend.extract(zip).lastPathComponent == "My Files 3")
    }

    @Test func plainGzipBecomesAFile() throws {
        let txt = try Fixtures.writeText("hello", to: dir.appendingPathComponent("notes.txt"))
        try ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/gzip"), ["-k", txt.path])
        try FileManager.default.removeItem(at: txt)
        let out = try ArchiveBackend.extract(dir.appendingPathComponent("notes.txt.gz"))
        #expect(out.lastPathComponent == "notes.txt")
        #expect(try contents(out) == "hello")
    }

    // Review Focus 5: an archive written inside the folder being archived must not include itself.
    @Test func archiveInsideSourceFolderExcludesItself() throws {
        let zip = folder.appendingPathComponent("backup.zip")
        try ArchiveBackend.create([folder], at: zip)
        let out = try ArchiveBackend.extract(zip, into: dir)
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("backup.zip").path))
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(!names.contains { $0.hasPrefix(".peel-") })
    }

    @Test func duplicateNamesAreRejected() throws {
        let other = dir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let a = try Fixtures.writeText("1", to: dir.appendingPathComponent("same.txt"))
        let b = try Fixtures.writeText("2", to: other.appendingPathComponent("same.txt"))
        #expect(throws: PeelError.self) { try ArchiveBackend.create([a, b], at: dir.appendingPathComponent("x.zip")) }
    }

    @Test func rejectsUnknownArchiveNames() throws {
        #expect(throws: PeelError.self) { try ArchiveBackend.create([folder], at: dir.appendingPathComponent("x.rar")) }
        let notArchive = try Fixtures.writeText("x", to: dir.appendingPathComponent("x.txt"))
        #expect(throws: PeelError.self) { try ArchiveBackend.extract(notArchive) }
    }

    @Test func rarNeedsUnar() throws {
        let rar = try Fixtures.writeText("x", to: dir.appendingPathComponent("x.rar"))
        #expect(throws: PeelError.missingTool(name: "unar", installHint: "brew install unar")) {
            try ArchiveBackend.extract(rar, locator: ToolLocator(searchPaths: []))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("x").path))
    }

    @Test func corruptZipLeavesNothingBehind() throws {
        let zip = try Fixtures.writeText("garbage", to: dir.appendingPathComponent("bad.zip"))
        #expect(throws: PeelError.self) { try ArchiveBackend.extract(zip) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("bad").path))
    }

    // Checkpoint 1 I1 ruling carried here: extracting next to an archive whose folder name matches must not touch it.
    @Test func forceExtractNeverReplacesTheFolderHoldingTheArchive() throws {
        let holder = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
        let zip = holder.appendingPathComponent("b.zip")
        try ArchiveBackend.create([folder], at: zip)
        let out = try ArchiveBackend.extract(zip, into: holder.deletingLastPathComponent(), planner: OutputPlanner(force: true))
        #expect(out.lastPathComponent == "My Files 2")
        #expect(FileManager.default.fileExists(atPath: zip.path))
    }

    // Final review I1: --force must never wipe an existing folder (it may hold files not in the archive).
    @Test func forceExtractNeverWipesAnExistingFolder() throws {
        let zip = dir.appendingPathComponent("My Files.zip")
        try ArchiveBackend.create([folder], at: zip)
        try Fixtures.writeText("precious", to: folder.appendingPathComponent("new-work.txt"))
        let out = try ArchiveBackend.extract(zip, planner: OutputPlanner(force: true))
        #expect(try contents(folder.appendingPathComponent("new-work.txt")) == "precious")
        #expect(out.lastPathComponent == "My Files 2")
    }

    // Final review I2: a lone top-level folder is not nested inside another folder of the same name.
    @Test func loneTopLevelFolderIsNotNested() throws {
        let zip = dir.appendingPathComponent("stuff.zip")
        try ArchiveBackend.create([folder], at: zip)
        let out = try ArchiveBackend.extract(zip, into: dir.appendingPathComponent("out"))
        #expect(out.lastPathComponent == "My Files")
        #expect(try contents(out.appendingPathComponent("résumé.txt")) == "a")
    }

    // Final review I3: zipping a symlinked folder archives the folder, not a dangling link.
    @Test func zipFollowsATopLevelFolderSymlink() throws {
        let link = dir.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let zip = dir.appendingPathComponent("l.zip")
        try ArchiveBackend.create([link], at: zip)
        let out = try ArchiveBackend.extract(zip, into: dir.appendingPathComponent("out"))
        #expect(out.lastPathComponent == "linkdir")
        #expect(try contents(out.appendingPathComponent("résumé.txt")) == "a")
    }

    // Stage 2 finding: zipping one file must store just that file, not its parent folder.
    @Test func zippingOneFileStoresOnlyTheFile() throws {
        let file = try Fixtures.writeText("x", to: dir.appendingPathComponent("d.txt"))
        let zip = dir.appendingPathComponent("d.zip")
        try ArchiveBackend.create([file], at: zip)
        let listing = try ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/unzip"), ["-Z1", zip.path]).stdout
        #expect(listing.split(separator: "\n").map(String.init) == ["d.txt"])
    }
}
