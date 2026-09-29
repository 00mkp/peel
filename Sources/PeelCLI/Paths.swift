import ArgumentParser
import ConvertKit
import Foundation

enum Paths {
    /// Command-line path → file URL. Expands "~"; a trailing "/" marks a folder.
    static func url(_ argument: String) -> URL {
        let expanded = argument.hasPrefix("~") ? (argument as NSString).expandingTildeInPath : argument
        return argument.hasSuffix("/") ? URL(fileURLWithPath: expanded, isDirectory: true) : URL(fileURLWithPath: expanded)
    }

    /// Path relative to the current directory when inside it, absolute otherwise.
    /// (/tmp, /var and /etc are symlinks into /private; both spellings count as the same place.)
    static func display(_ url: URL, cwd: String = FileManager.default.currentDirectoryPath) -> String {
        func normalized(_ path: String) -> String {
            for alias in ["/private/tmp", "/private/var", "/private/etc"] where path == alias || path.hasPrefix(alias + "/") {
                return String(path.dropFirst("/private".count))
            }
            return path
        }
        let base = normalized(URL(fileURLWithPath: cwd).standardizedFileURL.path) + "/"
        let path = normalized(url.standardizedFileURL.path)
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    static func requireExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw PeelError.fileNotFound(url) }
    }
}

/// Options shared by every command that writes files.
struct OutputOptions: ParsableArguments {
    @Option(name: [.short, .customLong("output")], help: "Output file or folder (a trailing / means folder).")
    var output: String?

    @Flag(help: "Overwrite existing files (never the input itself).")
    var force = false

    @Flag(help: "Show full tool output when something fails.")
    var verbose = false

    var planner: OutputPlanner { OutputPlanner(force: force) }
    var outputURL: URL? { output.map(Paths.url) }
    /// `-o` read as a folder, for commands that write several files.
    var outputDirectoryURL: URL? { output.map { URL(fileURLWithPath: Paths.url($0).path, isDirectory: true) } }
}
