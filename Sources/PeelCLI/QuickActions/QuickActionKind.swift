import ArgumentParser

/// The Finder Quick Actions peel installs.
public enum QuickActionKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case convert
    case merge = "merge-pdfs"
    case split = "split-pdf"
    case extractHere = "extract-here"
    case zip

    /// The title in Finder's Quick Actions / Services menu.
    public var menuTitle: String {
        switch self {
        case .convert: return "Peel - Convert To…"
        case .merge: return "Peel - Merge PDFs"
        case .split: return "Peel - Split PDF"
        case .extractHere: return "Peel - Extract Here"
        case .zip: return "Peel - Zip"
        }
    }

    public var bundleName: String {
        menuTitle.replacingOccurrences(of: "…", with: "") + ".workflow"
    }
}
