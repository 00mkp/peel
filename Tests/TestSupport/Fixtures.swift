import Foundation

public enum FixtureError: Error {
    case cannotCreate(URL)
}

/// Runtime generators for test inputs. Nothing binary is committed to the repo.
public enum Fixtures {
    /// A fresh, empty temporary directory, unique per call.
    public static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("peel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
