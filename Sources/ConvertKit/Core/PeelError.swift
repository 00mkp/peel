import Foundation

/// Every failure peel reports. Messages are one line and, where possible, say how to fix it.
public enum PeelError: Error, Equatable, LocalizedError {
    case fileNotFound(URL)
    case unknownFormat(URL)
    case unsupportedConversion(from: String, to: String)
    case missingTool(name: String, installHint: String)
    case invalidPageRange(String)
    case pageOutOfBounds(page: Int, count: Int)
    case unreadableFile(URL)
    case encryptedPDF(URL)
    case writeFailed(URL)
    /// `details` is the tool's full stderr, shown only with --verbose.
    case toolFailed(name: String, exitCode: Int32, lastLine: String, details: String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(url):
            return "no such file: \(url.path)"
        case let .unknownFormat(url):
            return "unrecognized file type: \(url.lastPathComponent) (run 'peel formats' to see what's supported)"
        case let .unsupportedConversion(from, to):
            return "can't convert .\(from) → \(to) (run 'peel formats file.\(from)' to see options)"
        case let .missingTool(name, hint):
            return "this needs \(name), which isn't installed → \(hint)"
        case let .invalidPageRange(text):
            return "invalid page range '\(text)' (examples: 3 · 1-3,5 · 8-)"
        case let .pageOutOfBounds(page, count):
            return "page \(page) is out of range (document has \(count) page\(count == 1 ? "" : "s"))"
        case let .unreadableFile(url):
            return "can't read \(url.lastPathComponent) (damaged, or not the format its name suggests)"
        case let .encryptedPDF(url):
            return "\(url.lastPathComponent) is password-protected (not supported yet)"
        case let .writeFailed(url):
            return "couldn't write \(url.path)"
        case let .toolFailed(name, code, lastLine, _):
            return "\(name) failed (exit \(code))" + (lastLine.isEmpty ? "" : ": \(lastLine)")
        case let .invalidArgument(message):
            return message
        }
    }
}
