import Foundation
import Testing
@testable import PeelCLI
import TestSupport

@Suite struct ArchiveCommandTests {
    @Test func zipThenExtract() throws {
        let dir = try Fixtures.tempDir()
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Fixtures.writeText("hi", to: folder.appendingPathComponent("a.txt"))

        #expect(runPeel(["zip", folder.path]).code == 0)
        let zip = dir.appendingPathComponent("stuff.zip")
        #expect(FileManager.default.fileExists(atPath: zip.path))

        let result = runPeel(["x", zip.path, "-o", dir.appendingPathComponent("out").path])
        #expect(result.code == 0)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("out/stuff/stuff/a.txt").path))
    }

    @Test func extractMissingFileFails() throws {
        let result = runPeel(["x", try Fixtures.tempDir().appendingPathComponent("nope.zip").path])
        #expect(result.code == 1)
        #expect(result.stderr.contains("no such file"))
    }

    @Test func zipNeedsInputs() {
        #expect(runPeel(["zip"]).code == 2)
    }

    // Checkpoint 1 I1 ruling carried here: -o naming an input must not replace it, even with --force.
    @Test func zipNeverOverwritesAnInput() throws {
        let dir = try Fixtures.tempDir()
        let old = try Fixtures.writeText("precious", to: dir.appendingPathComponent("old.zip"))
        let notes = try Fixtures.writeText("n", to: dir.appendingPathComponent("notes.txt"))
        #expect(runPeel(["zip", old.path, notes.path, "-o", old.path, "--force"]).code == 0)
        #expect(try String(contentsOf: old, encoding: .utf8) == "precious")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old 2.zip").path))
    }
}
