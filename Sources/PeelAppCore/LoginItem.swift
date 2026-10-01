import Foundation
import ServiceManagement

/// Whether peel opens at login.
public protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    /// Registered, but waiting for the person to allow it in System Settings → Login Items.
    var needsApproval: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// The real thing: macOS's own login item for this app (System Settings → General → Login Items).
public final class SystemLoginItem: LoginItem {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Opens System Settings → General → Login Items.
    public static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    public func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
