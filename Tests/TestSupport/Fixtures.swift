import ConvertKit
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

extension Fixtures {
    /// Whether an optional tool is installed (used to skip tests that need it).
    public static func has(_ tool: Tool) -> Bool {
        ToolLocator.standard.find(tool) != nil
    }

    /// Writes an executable shell script (used to fake tools).
    public static func makeExecutable(at url: URL, script: String) throws {
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
