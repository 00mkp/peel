import Foundation
import Testing
import TestSupport

/// Runs the real binary with PEEL_TOOL_PATH pointing at an empty folder: no optional tools, no Homebrew.
@Suite struct MissingToolTests {
    let dir: URL
    let noTools: URL

    init() throws {
        dir = try Fixtures.tempDir()
        noTools = dir.appendingPathComponent("no-tools")
        try FileManager.default.createDirectory(at: noTools, withIntermediateDirectories: true)
    }

    private func peel(_ arguments: [String]) throws -> (code: Int32, out: String, err: String) {
        try runBinary(arguments, environment: ["PEEL_TOOL_PATH": noTools.path])
    }

    @Test func webpExplainsWhatToInstall() throws {
        let png = try Fixtures.makeImage(at: dir.appendingPathComponent("a.png"), width: 20, height: 20, type: .png)
        let result = try peel(["convert", png.path, "--to", "webp"])
        #expect(result.code == 1)
        #expect(result.err.contains("cwebp"))
        #expect(result.err.contains("brew install webp"))
        #expect(result.err.contains("https://brew.sh"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.webp").path))
    }

    @Test func mediaWithoutFFmpeg() throws {
        let clip = try Fixtures.writeText("x", to: dir.appendingPathComponent("clip.mov"))
        let result = try peel(["media", "gif", clip.path])
        #expect(result.code == 1)
        #expect(result.err.contains("brew install ffmpeg"))
        #expect(result.err.contains("video/audio conversion"))  // what the tool adds (checkpoint A I2)
    }

    @Test func rarWithoutUnar() throws {
        let rar = try Fixtures.writeText("x", to: dir.appendingPathComponent("x.rar"))
        let result = try peel(["x", rar.path])
        #expect(result.code == 1)
        #expect(result.err.contains("brew install unar"))
    }

    @Test func svgWithoutRsvg() throws {
        let svg = try Fixtures.writeText("<svg/>", to: dir.appendingPathComponent("x.svg"))
        let result = try peel(["convert", svg.path, "--to", "png"])
        #expect(result.code == 1)
        #expect(result.err.contains("brew install librsvg"))
    }

    @Test func formatsMarksUnavailableTargets() throws {
        let result = try peel(["formats", "photo.heic"])
        #expect(result.code == 0)
        #expect(result.out.contains("webp  (needs cwebp → brew install webp)"))
        #expect(result.out.split(separator: "\n").contains("jpg"))
    }

    @Test func doctorListsEverythingMissing() throws {
        let result = try peel(["doctor"])
        #expect(result.code == 0)
        #expect(result.out.contains("✗ ffmpeg"))
        #expect(result.out.contains("✗ Homebrew"))
        #expect(result.out.contains("https://brew.sh"))
    }

    @Test func builtInFeaturesStillWork() throws {
        let a = try Fixtures.makePDF(at: dir.appendingPathComponent("a.pdf"), pages: 1)
        let b = try Fixtures.makePDF(at: dir.appendingPathComponent("b.pdf"), pages: 1)
        #expect(try peel(["pdf", "merge", a.path, b.path]).code == 0)
        let png = try Fixtures.makeImage(at: dir.appendingPathComponent("p.png"), width: 20, height: 20, type: .png)
        #expect(try peel(["convert", png.path, "--to", "jpg"]).code == 0)
    }
}
