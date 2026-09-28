import Foundation
import Testing
@testable import ConvertKit
import TestSupport

@Suite struct CancelTests {
    let dir: URL
    init() throws { dir = try Fixtures.tempDir() }

    @Test func cancelledMessage() {
        #expect(PeelError.cancelled.errorDescription == "cancelled")
    }

    @Test func converterSkipsRemainingFilesOnceCancelled() throws {
        let inputs = try (1...3).map {
            try Fixtures.makeImage(at: dir.appendingPathComponent("\($0).png"), width: 10, height: 10, type: .png)
        }
        var checks = 0
        let outcomes = Converter().convert(inputs, to: .jpg, isCancelled: { checks += 1; return checks > 1 })
        #expect((try? outcomes[0].result.get()) != nil)
        #expect(throws: PeelError.cancelled) { try outcomes[1].result.get() }
        #expect(throws: PeelError.cancelled) { try outcomes[2].result.get() }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("2.jpg").path))
    }

    @Test func tokenStartsUncancelled() {
        let token = CancelToken()
        #expect(!token.isCancelled)
        token.cancel()
        #expect(token.isCancelled)
    }

    // Review Focus 3: cancelling stops a running tool and leaves no partial output.
    @Test(.enabled(if: Fixtures.has(.ffmpeg)))
    func cancelStopsARunningTool() throws {
        let clip = dir.appendingPathComponent("long.mov")
        try ProcessRunner.runChecked(try ToolLocator.standard.require(.ffmpeg), [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=60:size=1280x720:rate=30", "-c:v", "mpeg4", "-q:v", "10", clip.path,
        ])
        let output = dir.appendingPathComponent("small.mp4")
        let token = CancelToken()
        let finished = DispatchSemaphore(value: 0)
        var failure: Error?
        DispatchQueue.global().async {
            do { try token.activate { try MediaBackend.compress(clip, to: output, targetBytes: nil) } } catch { failure = error }
            finished.signal()
        }
        func partials() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".peel-") }
        }
        let deadline = Date().addingTimeInterval(10)
        while partials().isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        token.cancel()
        #expect(finished.wait(timeout: .now() + 10) == .success)
        #expect(failure != nil)
        #expect(partials().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    // Cancelling one job must not stop tools that belong to other work.
    @Test func cancelOnlyStopsItsOwnTools() throws {
        let other = CancelToken()
        let finished = DispatchSemaphore(value: 0)
        var result: ProcessResult?
        DispatchQueue.global().async {
            result = try? ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["1"])
            finished.signal()
        }
        Thread.sleep(forTimeInterval: 0.2)
        other.cancel()
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(result?.exitCode == 0)
    }
}
