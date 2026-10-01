import AppKit
import Testing
@testable import PeelAppCore

@Suite struct PanelShortcutTests {
    private func match(_ key: String, _ flags: NSEvent.ModifierFlags = .command, editingText: Bool = false) -> PanelShortcut? {
        PanelShortcut(key: key, modifiers: flags, editingText: editingText)
    }

    @Test func mapsTheKeys() {
        #expect(match("o") == .chooseFiles)
        #expect(match("\r") == .run)
        #expect(match("\u{7F}") == .clear)
        #expect(match(",") == .settings)
        #expect(match("w") == .close)
        #expect(match("q") == .quit)
        #expect(match("\u{1B}", []) == .escape)
    }

    @Test func ignoresOtherCombinations() {
        #expect(match("o", []) == nil)                    // plain typing
        #expect(match("o", [.command, .shift]) == nil)
        #expect(match("x") == nil)
        #expect(match("\u{1B}", .command) == nil)
        #expect(match("o", [.command, .capsLock]) == .chooseFiles)   // caps lock doesn't matter
    }

    @Test func leavesTextEditingKeysToTheTextField() {
        #expect(match("\u{7F}", editingText: true) == nil)    // ⌘⌫ deletes to line start in a field
        #expect(match("o", editingText: true) == .chooseFiles)
    }

    @MainActor @Test func escapeLeavesSettingsBeforeClosing() {
        let model = AppModel(loginItem: FakeLoginItem())
        model.showingSettings = true
        #expect(model.handleEscape() == true)        // handled: back to the main view
        #expect(!model.showingSettings)
        #expect(model.handleEscape() == false)       // not handled: the panel should close
    }
}
