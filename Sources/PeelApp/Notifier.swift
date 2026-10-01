import Foundation
import UserNotifications

/// Posts wheel results as notifications (asks for permission once); clicking one opens the panel.
/// When notifications aren't allowed, `fallback` runs instead (the app shows the panel's results).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    var onOpen: () -> Void = {}

    /// Call at launch so clicks on notifications from earlier runs also open the panel.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func post(_ text: String, fallback: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let content = UNMutableNotificationContent()
            content.title = "peel"
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if error != nil { DispatchQueue.main.async(execute: fallback) }
            }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { send() } else { DispatchQueue.main.async(execute: fallback) }
                }
            default:
                DispatchQueue.main.async(execute: fallback)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
