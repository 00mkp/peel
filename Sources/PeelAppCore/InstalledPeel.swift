import ConvertKit
import Foundation

/// The installed `peel` command. The app's Update and Uninstall run it, so the menu does exactly
/// what `peel update` / `peel uninstall` do in a terminal.
public enum InstalledPeel {
    /// The recorded install's CLI, else install.sh's default (~/.local/bin/peel).
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        var candidates: [URL] = []
        if let prefix = KeyValueFile.read(PeelSupport.installRecord(home: home))?["prefix"] {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent("bin/peel"))
        }
        candidates.append(home.appendingPathComponent(".local/bin/peel"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// What `peel update --check` said.
public enum UpdateCheck: Equatable, Sendable {
    case upToDate(String)     // installed version
    case available(String)    // "0.3.0 -> 0.4.0 (2 new commits)"
    case failed(String)

    public init(exitCode: Int32, stdout: String, stderr: String) {
        let firstOut = stdout.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if exitCode == 0, let version = firstOut.between("peel: up to date (", and: ")") {
            self = .upToDate(version)
        } else if exitCode == 0, firstOut.hasPrefix("peel: update available: ") {
            self = .available(String(firstOut.dropFirst("peel: update available: ".count)))
        } else if let line = stderr.split(whereSeparator: \.isNewline).first, line.hasPrefix("peel: ") {
            self = .failed(String(line.dropFirst("peel: ".count)))
        } else {
            self = .failed("the check failed (exit \(exitCode))")
        }
    }
}

private extension String {
    func between(_ start: String, and end: String) -> String? {
        guard hasPrefix(start), hasSuffix(end) else { return nil }
        return String(dropFirst(start.count).dropLast(end.count))
    }
}
