import Testing
@testable import PeelCLI

@Suite struct PeelRootTests {
    @Test func versionExitsZero() {
        let result = runPeel(["--version"])
        #expect(result.code == 0)
        #expect(result.stdout.contains("0.1.0"))
    }

    @Test func unknownArgumentIsUsageError() {
        #expect(runPeel(["--frobnicate"]).code == 2)
    }
}
