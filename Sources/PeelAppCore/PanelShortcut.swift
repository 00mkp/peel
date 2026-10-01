import AppKit

/// Keyboard shortcuts while the menu-bar panel is open (the gear menu shows them too).
public enum PanelShortcut: Equatable, Sendable {
    case chooseFiles   // ⌘O
    case run           // ⌘↩
    case clear         // ⌘⌫
    case settings      // ⌘,
    case close         // ⌘W
    case quit          // ⌘Q
    case escape        // Esc: leave Settings, otherwise close the panel

    /// `key` is the event's characters ignoring modifiers. `editingText`: a text field has focus, so
    /// keys that edit text there (⌘⌫) stay with it.
    public init?(key: String, modifiers: NSEvent.ModifierFlags, editingText: Bool) {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        if flags.isEmpty, key == "\u{1B}" { self = .escape; return }
        guard flags == .command else { return nil }
        switch key {
        case "o": self = .chooseFiles
        case "\r": self = .run
        case "\u{7F}" where !editingText: self = .clear
        case ",": self = .settings
        case "w": self = .close
        case "q": self = .quit
        default: return nil
        }
    }
}
