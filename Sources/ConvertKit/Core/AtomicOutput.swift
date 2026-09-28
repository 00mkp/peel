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
        do {
            try body(temp)
            guard fm.fileExists(atPath: temp.path) else { throw PeelError.writeFailed(destination) }
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: temp, to: destination)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
