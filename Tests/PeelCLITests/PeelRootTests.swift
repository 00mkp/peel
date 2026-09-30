import ConvertKit
import Testing
@testable import PeelCLI

@Suite struct PeelRootTests {
    @Test func versionExitsZero() {
        let result = runPeel(["--version"])
        #expect(result.code == 0)
        #expect(result.stdout.contains(PeelVersion.current))
    }

    @Test func unknownArgumentIsUsageError() {
        #expect(runPeel(["--frobnicate"]).code == 2)
    }
}
