import ConvertKit
import Foundation
import Testing
@testable import PeelCLI
import TestSupport

@Suite struct MediaCommandTests {
    @Test func badTimeIsUsageError() {
        #expect(runPeel(["media", "trim", "a.mp4", "--from", "abc", "--to", "5"]).code == 2)
    }

    @Test func endBeforeStartIsUsageError() {
        #expect(runPeel(["media", "trim", "a.mp4", "--from", "0:10", "--to", "0:05"]).code == 2)
    }

    @Test func audioTargetMustBeAudio() {
        #expect(runPeel(["media", "audio", "a.mp4", "--to", "png"]).code == 2)
    }

    @Test func badSizeIsUsageError() {
        #expect(runPeel(["media", "compress", "a.mp4", "--size", "huge"]).code == 2)
    }

    @Test(.enabled(if: Fixtures.has(.ffmpeg)))
    func gifEndToEnd() throws {
        let dir = try Fixtures.tempDir()
        let clip = dir.appendingPathComponent("clip.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=10", "-c:v", "mpeg4", clip.path,
        ])
        let result = runPeel(["media", "gif", clip.path, "--fps", "5", "--width", "100"])
        #expect(result.code == 0)
        #expect(Fixtures.imageInfo(dir.appendingPathComponent("clip.gif"))?.width == 100)
    }
}
