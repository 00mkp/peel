import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct OutputPlannerTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func touch(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    @Test func splitsNames() {
        #expect(OutputPlanner.splitName("backup.tar.gz") == ("backup", "tar.gz"))
        #expect(OutputPlanner.splitName("photo.JPG") == ("photo", "JPG"))
        #expect(OutputPlanner.splitName("Makefile") == ("Makefile", ""))
        #expect(OutputPlanner.splitName(".bashrc") == (".bashrc", ""))
        #expect(OutputPlanner.splitName("my.report.pdf") == ("my.report", "pdf"))
    }

    @Test func plansNextToInput() {
        let input = dir.appendingPathComponent("photo.heic")
        #expect(OutputPlanner().plan(input: input, ext: "jpg") == dir.appendingPathComponent("photo.jpg"))
        #expect(OutputPlanner().plan(input: input, suffix: "-merged", ext: "pdf")
            == dir.appendingPathComponent("photo-merged.pdf"))
    }

    @Test func numbersCollisions() {
        let input = dir.appendingPathComponent("photo.heic")
        _ = touch("photo.jpg")
        #expect(OutputPlanner().plan(input: input, ext: "jpg").lastPathComponent == "photo 2.jpg")
        _ = touch("photo 2.jpg")
        #expect(OutputPlanner().plan(input: input, ext: "jpg").lastPathComponent == "photo 3.jpg")
    }

    @Test func numbersCompoundExtensions() {
        _ = touch("backup.tar.gz")
        #expect(OutputPlanner().resolve(dir.appendingPathComponent("backup.tar.gz")).lastPathComponent
            == "backup 2.tar.gz")
    }

    @Test func honoursOutputDirectoryAndFile() {
        let input = dir.appendingPathComponent("a.pdf")
        let existingDir = dir.appendingPathComponent("existing")
        try? FileManager.default.createDirectory(at: existingDir, withIntermediateDirectories: true)
        #expect(OutputPlanner().plan(input: input, ext: "txt", output: URL(fileURLWithPath: existingDir.path))
            == existingDir.appendingPathComponent("a.txt"))
        let newDir = URL(fileURLWithPath: dir.appendingPathComponent("new").path, isDirectory: true)
        #expect(OutputPlanner().plan(input: input, ext: "txt", output: newDir).lastPathComponent == "a.txt")
        #expect(OutputPlanner().plan(input: input, ext: "txt", output: newDir).deletingLastPathComponent().lastPathComponent == "new")
        let file = dir.appendingPathComponent("custom.txt")
        #expect(OutputPlanner().plan(input: input, ext: "txt", output: file) == file)
    }

    @Test func forceOverwritesOtherFiles() {
        let existing = touch("out.jpg")
        #expect(OutputPlanner(force: true).resolve(existing) == existing)
    }

    // Review Focus 1: --force must never target the input itself.
    @Test func forceNeverTargetsTheInput() {
        let input = touch("a.jpg")
        let planned = OutputPlanner(force: true).plan(input: input, ext: "jpg")
        #expect(planned.lastPathComponent == "a 2.jpg")
    }

    @Test func extensionlessOutput() {
        let input = dir.appendingPathComponent("notes.txt.gz")
        #expect(OutputPlanner().plan(input: input, ext: "").lastPathComponent == "notes.txt")
    }
}
