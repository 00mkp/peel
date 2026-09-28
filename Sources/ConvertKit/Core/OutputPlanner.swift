import Foundation

/// Decides where outputs go. Default: next to the input, same base name, new extension.
/// Existing files are never overwritten unless `force` — and never the input itself.
public struct OutputPlanner: Sendable {
    public var force: Bool

    public init(force: Bool = false) {
        self.force = force
    }

    private static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz"]

    /// "backup.tar.gz" → ("backup", "tar.gz"); "photo.JPG" → ("photo", "JPG"); "Makefile" → ("Makefile", "").
    public static func splitName(_ filename: String) -> (base: String, ext: String) {
        let lower = filename.lowercased()
        for compound in compoundExtensions where lower.hasSuffix("." + compound) && lower.count > compound.count + 1 {
            let dot = filename.index(filename.endIndex, offsetBy: -(compound.count + 1))
            return (String(filename[..<dot]), String(filename[filename.index(after: dot)...]))
        }
        guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex,
              filename.index(after: dot) != filename.endIndex else {
            return (filename, "")
        }
        return (String(filename[..<dot]), String(filename[filename.index(after: dot)...]))
    }

    /// An output URL counts as a folder if it is an existing directory or was written with a trailing "/".
    public static func isDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Plans one output derived from `input`.
    /// - Parameter output: the user's `-o`: nil → next to the input; a folder → inside it; a file → exactly that.
    public func plan(input: URL, suffix: String = "", ext: String, output: URL? = nil) -> URL {
        let base = Self.splitName(input.lastPathComponent).base
        let name = ext.isEmpty ? base + suffix : base + suffix + "." + ext
        let target: URL
        if let output {
            target = Self.isDirectory(output) ? output.appendingPathComponent(name) : output
        } else {
            target = input.deletingLastPathComponent().appendingPathComponent(name)
        }
        return resolve(target, avoiding: input)
    }

    /// Returns `url` if it is free (or `force` is set and it isn't `input`);
    /// otherwise the first free "name 2.ext", "name 3.ext", …
    public func resolve(_ url: URL, avoiding input: URL? = nil) -> URL {
        let fm = FileManager.default
        let isInput = input.map { $0.standardizedFileURL.path == url.standardizedFileURL.path } ?? false
        if force && !isInput { return url }
        guard isInput || fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let (base, ext) = Self.splitName(url.lastPathComponent)
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
