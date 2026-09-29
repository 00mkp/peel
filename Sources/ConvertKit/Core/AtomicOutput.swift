import Foundation

/// Writes outputs via a hidden temp item in the destination folder, then moves it into place,
/// so a failed operation never leaves a partial file (or folder) behind.
public enum AtomicOutput {
    public static func write(to destination: URL, _ body: (_ temp: URL) throws -> Void) throws {
        let fm = FileManager.default
        let dir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = OutputPlanner.splitName(destination.lastPathComponent).ext
        let temp = dir.appendingPathComponent(".peel-\(UUID().uuidString)" + (ext.isEmpty ? "" : "." + ext))
        InterruptCleanup.track(temp)
        defer { InterruptCleanup.untrack(temp) }
        do {
            try body(temp)
            var tempIsFolder: ObjCBool = false
            guard fm.fileExists(atPath: temp.path, isDirectory: &tempIsFolder) else { throw PeelError.writeFailed(destination) }
            var destinationIsFolder: ObjCBool = false
            if fm.fileExists(atPath: destination.path, isDirectory: &destinationIsFolder) {
                guard destinationIsFolder.boolValue == tempIsFolder.boolValue else {
                    let existing = destinationIsFolder.boolValue ? "folder" : "file"
                    let new = tempIsFolder.boolValue ? "folder" : "file"
                    throw PeelError.invalidArgument("won't replace the \(existing) \(destination.lastPathComponent) with a \(new)")
                }
                // Atomic swap: the existing item survives if the replacement fails.
                _ = try fm.replaceItemAt(destination, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: destination)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}

/// Several outputs that should appear together (the pages of one PDF): each is written to a hidden
/// temp next to its destination, and nothing replaces an existing file until `commit()` — so a
/// cancelled or failed run leaves every existing file as it was. `discard()` removes the temps.
public final class AtomicBatch {
    private var staged: [(temp: URL, destination: URL)] = []

    public init() {}

    public func write(to destination: URL, _ body: (_ temp: URL) throws -> Void) throws {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isFolder), isFolder.boolValue {
            throw PeelError.invalidArgument("won't replace the folder \(destination.lastPathComponent) with a file")
        }
        let dir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = OutputPlanner.splitName(destination.lastPathComponent).ext
        let temp = dir.appendingPathComponent(".peel-\(UUID().uuidString)" + (ext.isEmpty ? "" : "." + ext))
        InterruptCleanup.track(temp)
        do {
            try body(temp)
            guard fm.fileExists(atPath: temp.path) else { throw PeelError.writeFailed(destination) }
            staged.append((temp, destination))
        } catch {
            try? fm.removeItem(at: temp)
            InterruptCleanup.untrack(temp)
            throw error
        }
    }

    /// Moves every staged output into place (replacing existing files atomically).
    public func commit() throws {
        let fm = FileManager.default
        for (temp, destination) in staged {
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: destination)
            }
            InterruptCleanup.untrack(temp)
        }
        staged = []
    }

    public func discard() {
        for (temp, _) in staged {
            try? FileManager.default.removeItem(at: temp)
            InterruptCleanup.untrack(temp)
        }
        staged = []
    }
}
