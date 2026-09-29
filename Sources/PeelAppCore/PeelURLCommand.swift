import Foundation

/// Commands the CLI sends to the app through the `peel://` URL scheme (`peel app …`).
public enum PeelURLCommand: Equatable, Sendable {
    case login(Bool)
    case panel

    public init?(url: URL) {
        guard url.scheme == "peel" else { return nil }
        switch (url.host, url.pathComponents.dropFirst().first) {
        case ("login", "on"): self = .login(true)
        case ("login", "off"): self = .login(false)
        case ("panel", _): self = .panel
        default: return nil
        }
    }
}
