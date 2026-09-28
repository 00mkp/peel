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
