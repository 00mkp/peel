import Foundation

public enum TextFile {
    /// Reads text as UTF-16 (when it has a BOM) or UTF-8, falling back to Windows-1252 and then
    /// Latin-1 (which accepts any bytes). A leading BOM is dropped.
    public static func read(_ url: URL) throws -> String {
        guard let data = FileManager.default.contents(atPath: url.path) else { throw PeelError.unreadableFile(url) }
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        var text = (hasUTF16BOM ? String(data: data, encoding: .utf16) : nil)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// Writes UTF-8 text atomically.
    public static func write(_ text: String, to url: URL) throws {
        try AtomicOutput.write(to: url) { temp in try Data(text.utf8).write(to: temp) }
    }
}
