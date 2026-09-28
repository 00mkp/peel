import Foundation

/// One subtitle cue; times in milliseconds.
public struct Cue: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var text: String

    public init(start: Int, end: Int, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// SRT / VTT / TXT in pure Swift.
public enum SubtitleBackend {
    /// Parses SRT or VTT. Handles BOM, CRLF, VTT headers, NOTE/STYLE blocks, cue identifiers and settings.
    public static func parse(_ contents: String) throws -> [Cue] {
        var text = contents
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        var blocks: [[String]] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var cues: [Cue] = []
        for block in blocks {
            guard let timing = block.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = block[timing].components(separatedBy: "-->")
            let endToken = sides.count == 2
                ? sides[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                : ""
            guard sides.count == 2,
                  let start = parseTimestamp(sides[0].trimmingCharacters(in: .whitespaces)),
                  let end = parseTimestamp(endToken) else {
                throw PeelError.invalidArgument("bad subtitle timing line: \(block[timing])")
            }
            cues.append(Cue(start: start, end: end, text: block[(timing + 1)...].joined(separator: "\n")))
        }
        guard !cues.isEmpty else { throw PeelError.invalidArgument("no subtitle cues found") }
        return cues
    }

    /// "HH:MM:SS,mmm", "MM:SS.mmm", "H:MM:SS.m" → milliseconds.
    public static func parseTimestamp(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let secondsPart = parts[parts.count - 1].replacingOccurrences(of: ",", with: ".")
        let secondsSplit = secondsPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(secondsSplit.count), let seconds = Int(secondsSplit[0]) else { return nil }
        var millis = 0
        if secondsSplit.count == 2 {
            let fraction = String(secondsSplit[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            guard let value = Int(fraction) else { return nil }
            millis = value
        }
        guard let minutes = Int(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Int(parts[0]) : 0
        guard let hours else { return nil }
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
    }

    public static func formatTimestamp(_ ms: Int, separator: Character) -> String {
        let hours = ms / 3_600_000
        let minutes = ms / 60_000 % 60
        let seconds = ms / 1000 % 60
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, String(separator), ms % 1000)
    }

    public static func render(_ cues: [Cue], as format: FileFormat) throws -> String {
        switch format {
        case .srt:
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(formatTimestamp(cue.start, separator: ",")) --> \(formatTimestamp(cue.end, separator: ","))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .vtt:
            return "WEBVTT\n\n" + cues.map { cue in
                "\(formatTimestamp(cue.start, separator: ".")) --> \(formatTimestamp(cue.end, separator: "."))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .txt:
            return cues.map(\.text).joined(separator: "\n") + "\n"
        default:
            throw PeelError.unsupportedConversion(from: "srt", to: format.rawValue)
        }
    }

    public static func convert(_ input: URL, to output: URL, format: FileFormat) throws {
        let cues = try parse(try TextFile.read(input))
        try TextFile.write(try render(cues, as: format), to: output)
    }
}
