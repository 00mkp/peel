import Carbon.HIToolbox
import Foundation
import os

/// Claims a system-wide key combination. macOS refuses a combination this app already holds, but
/// not one another app holds (both then get it), so a clash with another app can't be detected.
public protocol HotKeyRegistrar: AnyObject {
    func register(onPress: @escaping () -> Void) -> Bool
    func unregister()
}

/// macOS's own hot keys (Carbon's RegisterEventHotKey): system-wide, and no Accessibility permission.
public final class CarbonHotKey: HotKeyRegistrar {
    public let keyCode: UInt32
    public let modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?
    private static var nextID: UInt32 = 1

    /// Default: ⌃⌥P.
    public init(keyCode: UInt32 = UInt32(kVK_ANSI_P), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    deinit { unregister() }

    public func register(onPress: @escaping () -> Void) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x7065_656C), id: Self.nextID)   // 'peel'
        Self.nextID += 1
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            hotKey = nil
            return false
        }
        self.onPress = onPress
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let key = Unmanaged<CarbonHotKey>.fromOpaque(context).takeUnretainedValue()
            guard pressedID.signature == OSType(0x7065_656C), key.isMine(pressedID) else { return OSStatus(eventNotHandledErr) }
            key.onPress?()
            return noErr
        }, 1, &pressed, me, &handler)
        registeredID = id.id
        return true
    }

    private var registeredID: UInt32 = 0
    private func isMine(_ id: EventHotKeyID) -> Bool { hotKey != nil && id.id == registeredID }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        onPress = nil
    }
}

/// The "open the panel with ⌃⌥P" setting: on by default, remembered, and says so if macOS refuses it.
@MainActor
public final class GlobalShortcut: ObservableObject {
    public static let label = "⌃⌥P"
    private static let key = "globalShortcutEnabled"

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var error: String?
    private let hotKey: HotKeyRegistrar
    private let defaults: UserDefaults
    private var onPress: () -> Void = {}

    public init(hotKey: HotKeyRegistrar = CarbonHotKey(), defaults: UserDefaults = .standard) {
        self.hotKey = hotKey
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    /// Call once at launch with what the shortcut does.
    public func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        apply()
    }

    public func setEnabled(_ on: Bool) {
        isEnabled = on
        defaults.set(on, forKey: Self.key)
        apply()
    }

    private static let log = Logger(subsystem: "dev.peel.app", category: "shortcut")

    private func apply() {
        hotKey.unregister()
        error = nil
        guard isEnabled else { return Self.log.notice("global shortcut off") }
        // Hot-key events arrive on the main thread (the application event target).
        let press = onPress
        if hotKey.register(onPress: { Self.log.notice("global shortcut pressed"); press() }) {
            Self.log.notice("global shortcut \(Self.label, privacy: .public) registered")
        } else {
            error = "macOS didn't let peel use \(Self.label)."
            Self.log.error("global shortcut \(Self.label, privacy: .public) could not be registered")
        }
    }
}
