import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

/// Deferred review minors in the CLI and Quick Actions, fixed.
@Suite struct LeftoverCLITests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func pdf(_ name: String, pages: Int = 2) throws -> URL {
        try Fixtures.makePDF(at: dir.appendingPathComponent(name), pages: pages)
    }
    private func png(_ name: String) throws -> URL {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: 20, height: 20, type: .png)
    }

    @Test func displayIsRelativeEvenThroughTheTmpSymlink() {
        #expect(Paths.display(URL(fileURLWithPath: "/tmp/x/a.pdf"), cwd: "/private/tmp/x") == "a.pdf")
        #expect(Paths.display(URL(fileURLWithPath: "/private/tmp/x/a.pdf"), cwd: "/tmp/x") == "a.pdf")
    }

    @Test func mergeFailureIsLabelled() throws {
        let result = runPeel(["pdf", "merge", try pdf("a.pdf").path, dir.appendingPathComponent("gone.pdf").path])
        #expect(result.code == 1)
        #expect(result.stderr.hasPrefix("✗ merge: no such file"))
    }

    @Test func splitRefusesAFileNameForItsOutputFolder() throws {
        #expect(runPeel(["pdf", "split", try pdf("a.pdf").path, "-o", dir.appendingPathComponent("one.pdf").path]).code == 2)
    }

    @Test func convertRefusesAnOutputNameWithTheWrongExtension() throws {
        let result = runPeel(["convert", try png("a.png").path, "--to", "jpg", "-o", dir.appendingPathComponent("b.png").path])
        #expect(result.code == 2)
        #expect(result.stderr.contains(".png"))
    }

    @Test func batchRefusesAnExistingFileAsItsOutputFolder() throws {
        let existing = try Fixtures.writeText("x", to: dir.appendingPathComponent("existing.txt"))
        #expect(runPeel(["convert", try png("a.png").path, try png("b.png").path, "--to", "jpg", "-o", existing.path]).code == 2)
    }

    @Test func qualityOnALosslessFormatGetsANote() throws {
        let result = runPeel(["convert", try png("a.png").path, "--to", "tiff", "--quality", "50"])
        #expect(result.code == 0)
        #expect(result.stderr.contains("--quality is ignored"))
    }

    @Test func zipIntoAFolder() throws {
        let file = try Fixtures.writeText("x", to: dir.appendingPathComponent("notes.txt"))
        let out = dir.appendingPathComponent("out", isDirectory: true)
        #expect(runPeel(["zip", file.path, "-o", out.path + "/"]).code == 0)
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("notes.zip").path))
    }

    @Test func homebrewNoteOncePerRun() throws {
        let empty = dir.appendingPathComponent("no-tools")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let result = try runBinary(["convert", try png("a.png").path, try png("b.png").path, "--to", "webp"],
                                   environment: ["PEEL_TOOL_PATH": empty.path])
        #expect(result.err.components(separatedBy: "brew.sh").count - 1 == 1)
    }

    @Test func emptyToolPathMeansUnset() throws {
        let result = try runBinary(["doctor"], environment: ["PEEL_TOOL_PATH": ""])
        #expect(result.out.contains("✓ ffmpeg") || !Fixtures.has(.ffmpeg))
    }

    @Test func quickActionWordingForExtractAndGroupedFailures() throws {
        let ui = FakeUI()
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Fixtures.writeText("x", to: folder.appendingPathComponent("a.txt"))
        let zip = dir.appendingPathComponent("stuff.zip")
        try ArchiveBackend.create([folder], at: zip)
        let handler = QuickActionHandler(ui: ui, runner: ActionRunner(), locator: .standard)
        _ = handler.handle(.extractHere, files: [zip])
        #expect(ui.notifications.last?.hasPrefix("Extracted → ") == true)

        let fake = try Fixtures.writeText("not a pdf", to: dir.appendingPathComponent("fake.pdf"))
        _ = handler.handle(.merge, files: [try pdf("m.pdf"), fake])
        #expect(ui.alerts.last?.message.contains("m.pdf:") == false)   // not blamed on the first file
    }

    @Test func reinstallNeverReplacesSomeoneElsesWorkflow() throws {
        let services = dir.appendingPathComponent("Services")
        let theirs = services.appendingPathComponent(QuickActionKind.zip.bundleName).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: theirs, withIntermediateDirectories: true)
        try Fixtures.writeText("mine", to: theirs.appendingPathComponent("marker.txt"))
        let result = runPeel(["install-quick-actions", "--dir", services.path, "--peel-path", "/usr/bin/true"])
        #expect(FileManager.default.fileExists(atPath: theirs.appendingPathComponent("marker.txt").path))
        #expect(result.stderr.contains("already exists"))
    }

    // Review follow-up: only refuse -o when its extension is a *different known* format.
    @Test func outputExtensionCheckAllowsOtherNames() throws {
        let pdf = try pdf("in.pdf", pages: 1)
        #expect(runPeel(["convert", pdf.path, "--to", "txt", "-o", dir.appendingPathComponent("notes.md").path]).code == 0)
        #expect(runPeel(["convert", try png("a.png").path, "--to", "jpg", "-o", dir.appendingPathComponent("v1.2").path]).code == 0)
    }

    @Test func batchRefusesAFileNameThatLooksLikeAFormat() throws {
        let result = runPeel(["convert", try png("a.png").path, try png("b.png").path, "--to", "jpg",
                              "-o", dir.appendingPathComponent("pics.jpg").path])
        #expect(result.code == 2)
    }

    @Test func splitAcceptsAnExistingFolderNamedLikeAPDF() throws {
        let folder = dir.appendingPathComponent("existing.pdf")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(runPeel(["pdf", "split", try pdf("a.pdf").path, "-o", folder.path]).code == 0)
    }

    @Test func qualityNoteWording() throws {
        let result = runPeel(["convert", try png("a.png").path, "--to", "tiff", "--quality", "50"])
        #expect(result.stderr.contains("--quality is ignored for tiff"))
    }

    // Review follow-up: a failed install must fail (exit 1) with a readable message.
    @Test func installFailureIsReported() throws {
        let locked = dir.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let result = runPeel(["install-quick-actions", "--dir", locked.path, "--peel-path", "/usr/bin/true"])
        #expect(result.code == 1)
        #expect(!result.stderr.contains("NSCocoaErrorDomain"))
        #expect(!result.stdout.contains("Right-click"))
    }
}
