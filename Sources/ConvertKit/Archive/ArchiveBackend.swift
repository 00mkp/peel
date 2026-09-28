import Foundation

/// Extract anything / bundle files, using the tools built into macOS (plus unar for rar/7z).
public enum ArchiveBackend {
    static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    static let tar = URL(fileURLWithPath: "/usr/bin/tar")
    static let gzip = URL(fileURLWithPath: "/usr/bin/gzip")

    /// Extracts into a new folder named after the archive, inside `directory` (default: next to the archive).
    /// A plain `.gz` becomes a single file instead. Returns what was created.
    @discardableResult
    public static func extract(_ archive: URL, into directory: URL? = nil, planner: OutputPlanner = OutputPlanner(),
                               locator: ToolLocator = .standard) throws -> URL {
        guard FileManager.default.fileExists(atPath: archive.path) else { throw PeelError.fileNotFound(archive) }
        guard let format = FileFormat(url: archive), format.category == .archive else {
            throw PeelError.invalidArgument(
                "\(archive.lastPathComponent) isn't a supported archive (zip, tar, tar.gz, tar.bz2, tar.xz, gz, rar, 7z)")
        }
        let parent = directory ?? archive.deletingLastPathComponent()
        let base = OutputPlanner.splitName(archive.lastPathComponent).base

        if format == .gz {
            let out = planner.resolve(parent.appendingPathComponent(base), avoiding: [archive])
            try AtomicOutput.write(to: out) { temp in
                try ProcessRunner.runChecked(gzip, ["-dc", archive.path], stdoutTo: temp)
            }
            return out
        }

        let unar = (format == .rar || format == .sevenZip) ? try locator.require(.unar) : nil
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".peel-\(UUID().uuidString)", isDirectory: true)
        InterruptCleanup.track(staging)
        defer {
            try? fm.removeItem(at: staging)
            InterruptCleanup.untrack(staging)
        }
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        if let unar {
            try ProcessRunner.runChecked(unar, ["-quiet", "-no-directory", "-output-directory", staging.path, archive.path])
        } else if format == .zip {
            try ProcessRunner.runChecked(ditto, ["-x", "-k", archive.path, staging.path])
        } else {
            try ProcessRunner.runChecked(tar, ["-xf", archive.path, "-C", staging.path])
        }

        // Like Finder and oh-my-zsh's `x`: a lone top-level folder becomes the result instead of being nested.
        let entries = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .filter { !["__MACOSX", ".DS_Store"].contains($0.lastPathComponent) }
        var isFolder: ObjCBool = false
        let lone = entries.count == 1 && fm.fileExists(atPath: entries[0].path, isDirectory: &isFolder) && isFolder.boolValue
        let result = lone ? entries[0] : staging
        let name = lone ? entries[0].lastPathComponent : base
        // Folders are never replaced, even with --force: that would delete files that aren't in the archive.
        let destination = OutputPlanner(force: false)
            .resolve(parent.appendingPathComponent(name, isDirectory: true), avoiding: [archive])
        try fm.moveItem(at: result, to: destination)
        return destination
    }

    /// Bundles files/folders. The archive type comes from `output`'s name: .zip, .tar.gz, .tgz or .tar.
    /// Inputs are staged first (APFS clones), so an archive written inside an input folder can't include itself.
    public static func create(_ paths: [URL], at output: URL) throws {
        guard !paths.isEmpty else { throw PeelError.invalidArgument("nothing to archive") }
        for path in paths where !FileManager.default.fileExists(atPath: path.path) { throw PeelError.fileNotFound(path) }
        let name = output.lastPathComponent.lowercased()
        let kind: String
        if name.hasSuffix(".zip") { kind = "zip" }
        else if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { kind = "tgz" }
        else if name.hasSuffix(".tar") { kind = "tar" }
        else { throw PeelError.invalidArgument("archive name must end in .zip, .tar.gz, .tgz or .tar") }

        let fm = FileManager.default
        let names = paths.map(\.lastPathComponent)
        let isSymlink = { (url: URL) in (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil }
        // Archive in place when possible (no copy of the data). Stage (APFS clones) only for several inputs,
        // a top-level symlink (archive its target under the link's name), or an output inside an input.
        let outputInsideInput = paths.contains { input in
            var ancestor = output.deletingLastPathComponent()
            while ancestor.path != "/" {
                if OutputPlanner.sameFile(ancestor, input) { return true }
                ancestor = ancestor.deletingLastPathComponent()
            }
            return false
        }
        var root = paths[0].deletingLastPathComponent()
        var staging: URL?
        if paths.count > 1 || paths.contains(where: isSymlink) || outputInsideInput {
            let stage = fm.temporaryDirectory.appendingPathComponent("peel-stage-\(UUID().uuidString)", isDirectory: true)
            InterruptCleanup.track(stage)
            staging = stage
            root = stage
        }
        defer {
            if let staging {
                try? fm.removeItem(at: staging)
                InterruptCleanup.untrack(staging)
            }
        }
        if let staging {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for path in paths {
                let target = staging.appendingPathComponent(path.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else {
                    throw PeelError.invalidArgument("two inputs are both named \(path.lastPathComponent)")
                }
                try fm.copyItem(at: path.resolvingSymlinksInPath(), to: target)
            }
        }

        try AtomicOutput.write(to: output) { temp in
            switch kind {
            case "zip":
                if let staging {
                    // The staging folder's contents are the archive's top level.
                    try ProcessRunner.runChecked(ditto, ["-c", "-k", "--sequesterRsrc", staging.path, temp.path])
                } else {
                    try ProcessRunner.runChecked(ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent", paths[0].path, temp.path])
                }
            default:
                let flags = kind == "tar" ? "-cf" : "-czf"
                try ProcessRunner.runChecked(tar, [flags, temp.path, "-C", root.path] + names,
                                             environment: ["COPYFILE_DISABLE": "1"])
            }
        }
    }
}
