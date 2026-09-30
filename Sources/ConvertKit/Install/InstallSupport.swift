import Foundation

/// peel's version. Must match the repo's VERSION file (a test checks), which build scripts read.
public enum PeelVersion {
    public static let current = "0.3.0"
}

/// A tiny `key=value` per line file (install record, app state). Values may contain "=".
public struct KeyValueFile: Equatable, Sendable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }

    /// nil when the file doesn't exist or can't be read.
    public static func read(_ url: URL) -> KeyValueFile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            values[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        return KeyValueFile(values)
    }

    public func write(to url: URL) throws {
        let text = values.keys.sorted().map { "\($0)=\(values[$0] ?? "")\n" }.joined()
        try AtomicOutput.write(to: url) { temp in try Data(text.utf8).write(to: temp) }
    }
}

/// Where peel keeps its own small files: ~/Library/Application Support/peel.
public enum PeelSupport {
    public static func directory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/peel", isDirectory: true)
    }

    /// Written by install.sh: source checkout, install prefix, app folder, version.
    public static func installRecord(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directory(home: home).appendingPathComponent("install.conf")
    }

    /// Written by Peel.app so the CLI can report it: version, Open at Login state.
    public static func appState(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directory(home: home).appendingPathComponent("app-state.conf")
    }
}
