import Carbon.HIToolbox
import Foundation
import Testing
@testable import PeelAppCore

final class FakeHotKey: HotKeyRegistrar {
    var available = true
    private(set) var registered = false
    var press: (() -> Void)?
    func register(onPress: @escaping () -> Void) -> Bool {
        guard available else { return false }
        registered = true
        press = onPress
        return true
    }
    func unregister() { registered = false; press = nil }
}

@MainActor
@Suite struct GlobalShortcutTests {
    private func defaults() -> UserDefaults {
        let name = "peel-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func onByDefaultAndPressingItTogglesThePanel() {
        let hotKey = FakeHotKey()
        let shortcut = GlobalShortcut(hotKey: hotKey, defaults: defaults())
        var presses = 0
        shortcut.start { presses += 1 }
        #expect(shortcut.isEnabled && hotKey.registered && shortcut.error == nil)
        hotKey.press?()
        #expect(presses == 1)
    }

    @Test func turningItOffIsRemembered() {
        let store = defaults()
        let hotKey = FakeHotKey()
        let shortcut = GlobalShortcut(hotKey: hotKey, defaults: store)
        shortcut.start {}
        shortcut.setEnabled(false)
        #expect(!hotKey.registered)
        let next = FakeHotKey()
        let relaunched = GlobalShortcut(hotKey: next, defaults: store)
        relaunched.start {}
        #expect(!relaunched.isEnabled && !next.registered)
        relaunched.setEnabled(true)
        #expect(next.registered)
    }

    @Test func saysSoWhenMacOSRefusesTheKeys() {
        let hotKey = FakeHotKey()
        hotKey.available = false
        let shortcut = GlobalShortcut(hotKey: hotKey, defaults: defaults())
        shortcut.start {}
        #expect(shortcut.error == "macOS didn't let peel use ⌃⌥P.")
        shortcut.setEnabled(false)
        #expect(shortcut.error == nil)
    }

    // The real thing: macOS hands a combination to one owner, so a second claim on it fails.
    // (An unusual combination, so this never collides with a running peel's ⌃⌥P.)
    @Test func carbonHotKeyClaimsTheCombination() {
        let combo = (UInt32(kVK_F19), UInt32(controlKey | optionKey | shiftKey | cmdKey))
        let first = CarbonHotKey(keyCode: combo.0, modifiers: combo.1)
        let second = CarbonHotKey(keyCode: combo.0, modifiers: combo.1)
        #expect(first.register {})
        #expect(!second.register {})
        first.unregister()
        #expect(second.register {})
        second.unregister()
    }

    @Test func defaultsToControlOptionP() {
        let key = CarbonHotKey()
        #expect(key.keyCode == UInt32(kVK_ANSI_P))
        #expect(key.modifiers == UInt32(controlKey | optionKey))
    }
}
