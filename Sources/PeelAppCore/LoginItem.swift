import Foundation
import ServiceManagement

/// Whether Peel opens at login.
public protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// The real thing: macOS's own login item for this app (System Settings → General → Login Items).
public final class SystemLoginItem: LoginItem {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
