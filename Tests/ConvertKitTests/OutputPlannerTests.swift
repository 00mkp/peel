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

    // Checkpoint 1 C1: APFS is case-insensitive — IMG_0001.JPG → IMG_0001.jpg is the same file.
    @Test func forceNeverTargetsInputDifferingOnlyInCase() {
        let input = touch("IMG_0001.JPG")
        #expect(OutputPlanner(force: true).plan(input: input, ext: "jpg").lastPathComponent == "IMG_0001 2.jpg")
    }

    // Checkpoint 1 C1: an input reached through a symlink is still the input.
    @Test func forceNeverTargetsSymlinkedInput() throws {
        let real = touch("real.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let planned = OutputPlanner(force: true).plan(input: link, ext: "jpg", output: real)
        #expect(planned.lastPathComponent == "real 2.jpg")
    }

    // Checkpoint 1 I1: every input is protected, not just the one the name derives from.
    @Test func protectsEveryInput() {
        let a = touch("a.pdf")
        let b = touch("b.pdf")
        let planned = OutputPlanner(force: true).plan(input: a, suffix: "", ext: "pdf", output: b, protecting: [a, b])
        #expect(planned.lastPathComponent == "b 2.pdf")
    }

    // Checkpoint 1 I1: a folder that contains an input is never a replaceable target.
    @Test func neverTargetsAFolderContainingAnInput() throws {
        let folder = dir.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = folder.appendingPathComponent("b.zip")
        FileManager.default.createFile(atPath: archive.path, contents: Data("x".utf8))
        #expect(OutputPlanner(force: true).resolve(folder, avoiding: [archive]).lastPathComponent == "b 2")
    }

    @Test func numberingSkipsProtectedNamesNotYetOnDisk() {
        _ = touch("x.pdf")
        let planned = [dir.appendingPathComponent("x.pdf"), dir.appendingPathComponent("x 2.pdf")]
        #expect(OutputPlanner(force: true).resolve(dir.appendingPathComponent("x.pdf"), avoiding: planned).lastPathComponent
            == "x 3.pdf")
    }
}
