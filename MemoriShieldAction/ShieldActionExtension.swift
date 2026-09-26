import ManagedSettings
import UserNotifications
import Foundation

class ShieldActionExtension: ShieldActionDelegate {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.memori.shared")!

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, applicationToken: application, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, applicationToken: nil, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(action, applicationToken: nil, completionHandler: completionHandler)
    }

    private func handleAction(_ action: ShieldAction, applicationToken: ApplicationToken?, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // Increment daily attempt count
            let count = dailyAttemptCount
            sharedDefaults.set(count + 1, forKey: "focus_daily_attempt_count")
            sharedDefaults.set(Date(), forKey: "focus_daily_attempt_date")

            // Remember which app was blocked so the unlock flow can show its icon.
            if let token = applicationToken, let data = try? JSONEncoder().encode(token) {
                sharedDefaults.set(data, forKey: "unlock_last_app_token")
            }

            // Send a local notification that deep-links into the app
            sendUnlockNotification()

            // Close the shield (sends user to home screen, notification appears immediately)
            completionHandler(.close)

        case .secondaryButtonPressed:
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    private func sendUnlockNotification() {
        let content = UNMutableNotificationContent()
        content.title = "No feed til you train"
        content.body = "Tap to spin your brain game."
        content.sound = .default
        content.userInfo = ["deepLink": "memo://focus-unlock"]

        // Fire immediately
        let request = UNNotificationRequest(
            identifier: "focus_unlock_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )

        UNUserNotificationCenter.current().add(request)
    }

    private var dailyAttemptCount: Int {
        let savedDate = sharedDefaults.object(forKey: "focus_daily_attempt_date") as? Date
        if let savedDate, Calendar.current.isDateInToday(savedDate) {
            return sharedDefaults.integer(forKey: "focus_daily_attempt_count")
        }
        return 0
    }
}
