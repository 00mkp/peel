import Foundation

public enum TextFile {
    /// Reads text as UTF-8, falling back to Latin-1 (which accepts any bytes), minus a leading BOM.
    public static func read(_ url: URL) throws -> String {
        guard let data = FileManager.default.contents(atPath: url.path) else { throw PeelError.unreadableFile(url) }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// Writes UTF-8 text atomically.
    public static func write(_ text: String, to url: URL) throws {
        try AtomicOutput.write(to: url) { temp in try Data(text.utf8).write(to: temp) }
    }
}
