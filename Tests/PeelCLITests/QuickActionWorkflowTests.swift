import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

/// Installs the workflows into a temp folder (wired to the built binary and a log UI) and runs them
/// the way Finder does, via `automator -i`.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/automator")))
struct QuickActionWorkflowTests {
    let dir: URL
    let services: URL
    let log: URL

    init() throws {
        dir = try Fixtures.tempDir()
        services = dir.appendingPathComponent("Services")
        log = dir.appendingPathComponent("ui.log")
    }

    private func install(choice: String? = nil) throws {
        var arguments = ["install-quick-actions", "--dir", services.path, "--peel-path", peelBinary.path, "--test-log", log.path]
        if let choice { arguments += ["--test-choice", choice] }
        #expect(try runBinary(arguments).code == 0)
    }

    private func run(_ kind: QuickActionKind, on files: [URL]) throws {
        let input = files.map(\.path).joined(separator: "\n")
        _ = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/automator"),
                                  ["-i", input, services.appendingPathComponent(kind.bundleName).path])
    }

    private func logText() -> String { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }

    // Review Focus 5: spaces and accents survive Finder → workflow → peel.
    @Test func convertFromFinder() throws {
        try install(choice: "jpg")
        let photo = try Fixtures.makeImage(at: dir.appendingPathComponent("my phöto 1.png"), width: 10, height: 10, type: .png)
        try run(.convert, on: [photo])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("my phöto 1.jpg").path))
        #expect(logText().contains("notify: Converted → my phöto 1.jpg"))
    }

    @Test func mergeTwoSelectedPDFs() throws {
        try install()
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        let b = try Fixtures.makePDF(at: dir.appendingPathComponent("b.pdf"), pages: 1)
        try run(.merge, on: [a, b])
        #expect(Fixtures.pageTexts(dir.appendingPathComponent("a-merged.pdf")).count == 2)
    }

    @Test func splitExtractAndZip() throws {
        try install()
        let pdf = try Fixtures.makePDF(at: dir.appendingPathComponent("d.pdf"), pages: 2)
        try run(.split, on: [pdf])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("d-p2.pdf").path))
        try run(.zip, on: [pdf])
        let zip = dir.appendingPathComponent("d.zip")
        #expect(FileManager.default.fileExists(atPath: zip.path))
        try run(.extractHere, on: [zip])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("d 2/d.pdf").path)
                || FileManager.default.fileExists(atPath: dir.appendingPathComponent("d/d.pdf").path))
    }

    // Review Focus 1: the wrong selection produces a dialog, not silence.
    @Test func wrongSelectionShowsDialog() throws {
        try install()
        let png = try Fixtures.makeImage(at: dir.appendingPathComponent("p.png"), width: 10, height: 10, type: .png)
        try run(.merge, on: [png])
        #expect(logText().contains("alert: Merge PDFs needs two or more PDF files."))
    }

    // Checkpoint B I1: a failure peel already reported must not also fail the workflow (blank Automator error).
    @Test func reportedFailureDoesNotFailTheWorkflow() throws {
        try install()
        let png = try Fixtures.makeImage(at: dir.appendingPathComponent("q.png"), width: 10, height: 10, type: .png)
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/automator"),
                                           ["-i", png.path, services.appendingPathComponent(QuickActionKind.merge.bundleName).path])
        #expect(logText().contains("alert: Merge PDFs needs two or more PDF files."))
        #expect(result.exitCode == 0)
    }
}
