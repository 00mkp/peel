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
    public func plan(input: URL, suffix: String = "", ext: String, output: URL? = nil, protecting others: [URL] = []) -> URL {
        let base = Self.splitName(input.lastPathComponent).base
        let name = ext.isEmpty ? base + suffix : base + suffix + "." + ext
        let target: URL
        if let output {
            target = Self.isDirectory(output) ? output.appendingPathComponent(name) : output
        } else {
            target = input.deletingLastPathComponent().appendingPathComponent(name)
        }
        return resolve(target, avoiding: [input] + others)
    }

    /// Returns `url` if it is free (or `force` is set and it isn't protected);
    /// otherwise the first free "name 2.ext", "name 3.ext", …
    /// Protected: any of `inputs`, or a folder containing one of them.
    public func resolve(_ url: URL, avoiding inputs: [URL] = []) -> URL {
        let fm = FileManager.default
        let isProtected = Self.isProtected(url, inputs: inputs)
        if force && !isProtected { return url }
        guard isProtected || fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let (base, ext) = Self.splitName(url.lastPathComponent)
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            // Also skip protected names: outputs planned earlier in this run may not be on disk yet.
            if !fm.fileExists(atPath: candidate.path) && !Self.isProtected(candidate, inputs: inputs) { return candidate }
            n += 1
        }
    }

    /// Whether writing `url` could clobber an input: it is an input, or a folder containing one.
    /// Compared by file identity, so differences in letter case (APFS) and symlinks don't fool it.
    static func isProtected(_ url: URL, inputs: [URL]) -> Bool {
        for input in inputs {
            if input.standardizedFileURL.path == url.standardizedFileURL.path || sameFile(url, input) { return true }
            var ancestor = input.resolvingSymlinksInPath().deletingLastPathComponent()
            while ancestor.path != "/" {
                if sameFile(url, ancestor) { return true }
                ancestor = ancestor.deletingLastPathComponent()
            }
        }
        return false
    }

    /// Same file or folder on disk; false if either doesn't exist.
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        guard let idA = identifier(a), let idB = identifier(b) else { return false }
        return idA.isEqual(idB)
    }

    private static func identifier(_ url: URL) -> NSObject? {
        let resolved = URL(fileURLWithPath: url.resolvingSymlinksInPath().path)
        return (try? resolved.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }
}
