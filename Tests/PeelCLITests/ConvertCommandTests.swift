import Foundation
import Testing
@testable import PeelCLI
import TestSupport

@Suite struct ConvertCommandTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    private func png(_ name: String, alpha: Bool = false) throws -> String {
        try Fixtures.makeImage(at: dir.appendingPathComponent(name), width: 400, height: 300, type: .png, alpha: alpha).path
    }

    @Test func convertsWithResize() throws {
        let result = runPeel(["convert", try png("a.png"), "--to", "jpeg", "--width", "100"])
        #expect(result.code == 0)
        #expect(Fixtures.imageInfo(dir.appendingPathComponent("a.jpg"))?.width == 100)
    }

    // Review Focus 1 end-to-end: same-format resize with --force keeps the input.
    @Test func forceNeverOverwritesInput() throws {
        let input = try png("a.png")
        #expect(runPeel(["convert", input, "--to", "png", "--width", "100", "--force"]).code == 0)
        #expect(Fixtures.imageInfo(URL(fileURLWithPath: input))?.width == 400)
        #expect(Fixtures.imageInfo(dir.appendingPathComponent("a 2.png"))?.width == 100)
    }

    @Test func batchSummaryAndExitCode() throws {
        let result = runPeel(["convert", try png("a.png"), dir.appendingPathComponent("nope.png").path, "--to", "jpg"])
        #expect(result.code == 1)
        #expect(result.stdout.contains("converted 1/2 files (1 failed)"))
        #expect(result.stderr.contains("✗ nope.png"))
    }

    @Test func unknownTargetIsUsageError() throws {
        #expect(runPeel(["convert", try png("a.png"), "--to", "docx"]).code == 2)
    }

    @Test func badQualityIsUsageError() throws {
        #expect(runPeel(["convert", try png("a.png"), "--to", "jpg", "--quality", "0"]).code == 2)
    }

    @Test func formatsForAFile() {
        let result = runPeel(["formats", "photo.heic"])
        #expect(result.code == 0)
        #expect(result.out.contains("jpg"))
        #expect(result.out.contains("pdf"))
    }

    @Test func formatsTable() {
        let result = runPeel(["formats"])
        #expect(result.code == 0)
        #expect(result.out.contains { $0.hasPrefix("srt") })
    }

    @Test func formatsForArchivePointsToX() {
        #expect(runPeel(["formats", "a.zip"]).stdout.contains("peel x"))
    }
}
