import ConvertKit
import Foundation
import Testing
import TestSupport

/// Runs the real `peel` binary, because Ctrl-C handling only exists in the executable.
@Suite(.enabled(if: Fixtures.has(.ffmpeg)))
struct InterruptTests {
    static let binary = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/debug/peel")

    // Checkpoint 1 I4: Ctrl-C mid-encode must not leave a hidden partial file behind.
    @Test func interruptRemovesPartialOutput() throws {
        let dir = try Fixtures.tempDir()
        let clip = dir.appendingPathComponent("long.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=60:size=1280x720:rate=30", "-c:v", "mpeg4", "-q:v", "10", clip.path,
        ])
        let peel = Process()
        peel.executableURL = Self.binary
        peel.arguments = ["media", "compress", clip.path]
        peel.standardOutput = FileHandle.nullDevice
        peel.standardError = FileHandle.nullDevice
        try peel.run()

        func partials() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".peel-") }
        }
        let deadline = Date().addingTimeInterval(10)
        while partials().isEmpty && peel.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        #expect(!partials().isEmpty, "encode never started")
        Thread.sleep(forTimeInterval: 0.3)
        peel.interrupt()
        peel.waitUntilExit()

        #expect(peel.terminationStatus == 130)
        #expect(partials().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("long-compressed.mov").path))
    }
}
