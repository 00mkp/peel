import ConvertKit
import Testing
@testable import PeelCLI

@Suite struct DoctorCommandTests {
    @Test func reportsMissingToolsWithHints() {
        let lines = Doctor.report(locator: ToolLocator(searchPaths: []))
        #expect(lines.contains { $0.hasPrefix("✗ ffmpeg") && $0.contains("brew install ffmpeg") })
        #expect(lines.contains { $0.hasPrefix("✗ unar") && $0.contains("RAR") })
    }

    @Test func runsAndExitsZero() {
        let result = runPeel(["doctor"])
        #expect(result.code == 0)
        #expect(result.stdout.contains("ffmpeg"))
    }
}
