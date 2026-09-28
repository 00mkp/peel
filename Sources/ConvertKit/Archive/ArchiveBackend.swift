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
        let destination = planner.resolve(parent.appendingPathComponent(base, isDirectory: true), avoiding: [archive])
        try AtomicOutput.write(to: destination) { temp in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
            if let unar {
                try ProcessRunner.runChecked(unar, ["-quiet", "-no-directory", "-output-directory", temp.path, archive.path])
            } else if format == .zip {
                try ProcessRunner.runChecked(ditto, ["-x", "-k", archive.path, temp.path])
            } else {
                try ProcessRunner.runChecked(tar, ["-xf", archive.path, "-C", temp.path])
            }
        }
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
        let staging = fm.temporaryDirectory.appendingPathComponent("peel-stage-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for path in paths {
            let target = staging.appendingPathComponent(path.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else {
                throw PeelError.invalidArgument("two inputs are both named \(path.lastPathComponent)")
            }
            try fm.copyItem(at: path, to: target)
        }
        let names = paths.map(\.lastPathComponent)

        try AtomicOutput.write(to: output) { temp in
            switch kind {
            case "zip":
                try ProcessRunner.runChecked(ditto, ["-c", "-k", "--sequesterRsrc", staging.path, temp.path])
            default:
                let flags = kind == "tar" ? "-cf" : "-czf"
                try ProcessRunner.runChecked(tar, [flags, temp.path, "-C", staging.path] + names,
                                             environment: ["COPYFILE_DISABLE": "1"])
            }
        }
    }
}
