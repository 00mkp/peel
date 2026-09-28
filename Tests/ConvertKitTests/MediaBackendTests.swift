import Foundation
import Testing
@testable import ConvertKit
import TestSupport

private func hasPair(_ args: [String], _ a: String, _ b: String) -> Bool {
    zip(args, args.dropFirst()).contains { $0 == a && $1 == b }
}

@Suite struct MediaArgumentTests {
    let input = URL(fileURLWithPath: "/tmp/in put.mov")
    let output = URL(fileURLWithPath: "/tmp/out.mp4")

    @Test func parsesTimes() {
        #expect(MediaBackend.parseTime("90") == 90)
        #expect(MediaBackend.parseTime("1:30") == 90)
        #expect(MediaBackend.parseTime("01:02:03.5") == 3723.5)
        #expect(MediaBackend.parseTime("abc") == nil)
        #expect(MediaBackend.parseTime("1:2:3:4") == nil)
        #expect(MediaBackend.parseTime("-5") == nil)
    }

    @Test func parsesSizes() {
        #expect(MediaBackend.parseSize("25MB") == 25_000_000)
        #expect(MediaBackend.parseSize("500kb") == 500_000)
        #expect(MediaBackend.parseSize("1.5GB") == 1_500_000_000)
        #expect(MediaBackend.parseSize("1000") == 1000)
        #expect(MediaBackend.parseSize("0MB") == nil)
        #expect(MediaBackend.parseSize("big") == nil)
    }

    @Test func mp4Arguments() throws {
        let args = try MediaBackend.convertArguments(input: input, output: output, format: .mp4)
        #expect(hasPair(args, "-i", input.path))
        #expect(hasPair(args, "-c:v", "libx264"))
        #expect(hasPair(args, "-pix_fmt", "yuv420p"))
        #expect(hasPair(args, "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"))
        #expect(args.last == output.path)
    }

    @Test func audioArguments() throws {
        let mp3 = try MediaBackend.convertArguments(input: input, output: output, format: .mp3)
        #expect(mp3.contains("-vn") && hasPair(mp3, "-c:a", "libmp3lame"))
        let ogg = try MediaBackend.convertArguments(input: input, output: output, format: .ogg)
        #expect(hasPair(ogg, "-c:a", "libopus"))
    }

    @Test func nonMediaTargetIsUnsupported() {
        #expect(throws: PeelError.self) { try MediaBackend.convertArguments(input: input, output: output, format: .png) }
    }

    @Test func trimArguments() {
        let args = MediaBackend.trimArguments(input: input, output: output, from: 10, until: 45)
        #expect(hasPair(args, "-ss", "10.000"))
        #expect(hasPair(args, "-t", "35.000"))
        #expect(hasPair(args, "-c", "copy"))
    }

    @Test func gifArguments() {
        let args = MediaBackend.gifArguments(input: input, output: output, fps: 10, width: 320)
        #expect(args.contains { $0.hasPrefix("fps=10,scale=320:-1") && $0.contains("palettegen") })
    }

    @Test func bitrateForTargetSize() throws {
        #expect(try MediaBackend.videoBitrate(targetBytes: 25_000_000, duration: 100) == 1872)
        #expect(throws: PeelError.self) { try MediaBackend.videoBitrate(targetBytes: 100_000, duration: 600) }
    }

    @Test func missingFFmpegGivesHint() {
        #expect(throws: PeelError.missingTool(name: "ffmpeg", installHint: "brew install ffmpeg")) {
            try MediaBackend.convert(input, to: output, format: .mp4, locator: ToolLocator(searchPaths: []))
        }
    }
}

@Suite(.enabled(if: Fixtures.has(.ffmpeg) && Fixtures.has(.ffprobe)))
struct MediaIntegrationTests {
    let dir: URL
    let sample: URL

    /// 2-second 321×241 clip (odd size on purpose) with a sine-wave audio track.
    init() throws {
        dir = try Fixtures.tempDir()
        sample = dir.appendingPathComponent("sample clip.mov")
        let ffmpeg = try ToolLocator.standard.require(.ffmpeg)
        try ProcessRunner.runChecked(ffmpeg, [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=2:size=321x241:rate=10",
            "-f", "lavfi", "-i", "sine=duration=2", "-shortest",
            "-c:v", "mpeg4", "-c:a", "aac", sample.path,
        ])
    }

    // Review Focus 3: odd dimensions must still produce an MP4.
    @Test func oddSizedVideoToMP4() throws {
        let out = dir.appendingPathComponent("out.mp4")
        try MediaBackend.convert(sample, to: out, format: .mp4)
        #expect(abs(try MediaBackend.duration(of: out) - 2) < 0.3)
    }

    @Test func extractMP3() throws {
        let out = dir.appendingPathComponent("out.mp3")
        try MediaBackend.convert(sample, to: out, format: .mp3)
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func makeGIF() throws {
        let out = dir.appendingPathComponent("out.gif")
        try MediaBackend.gif(sample, to: out, fps: 5, width: 160)
        #expect(Fixtures.imageInfo(out)?.width == 160)
    }

    @Test func trimToOneSecond() throws {
        let out = dir.appendingPathComponent("trim.mov")
        try MediaBackend.trim(sample, to: out, from: 0, until: 1)
        #expect(abs(try MediaBackend.duration(of: out) - 1) < 0.4)
    }

    @Test func compressDefaultAndTargetSize() throws {
        let crf = dir.appendingPathComponent("c1.mp4")
        try MediaBackend.compress(sample, to: crf, targetBytes: nil)
        #expect(FileManager.default.fileExists(atPath: crf.path))
        let sized = dir.appendingPathComponent("c2.mp4")
        try MediaBackend.compress(sample, to: sized, targetBytes: 200_000)
        #expect(FileManager.default.fileExists(atPath: sized.path))
    }

    @Test func failureLeavesNoPartialFile() throws {
        let bogus = try Fixtures.writeText("not video", to: dir.appendingPathComponent("bogus.mov"))
        let out = dir.appendingPathComponent("bogus.mp4")
        #expect(throws: PeelError.self) { try MediaBackend.convert(bogus, to: out, format: .mp4) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
