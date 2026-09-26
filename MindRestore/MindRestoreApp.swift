import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct MindRestoreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Analytics.configure()
        configureTabBarAppearance()
    }

    private func configureTabBarAppearance() {
        // Force non-translucent tab bar to avoid iOS 26 Liquid Glass black icons
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground

        let gray = UIColor(white: 0.55, alpha: 1.0)
        appearance.stackedLayoutAppearance.normal.iconColor = gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: gray]
        appearance.inlineLayoutAppearance.normal.iconColor = gray
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: gray]
        appearance.compactInlineLayoutAppearance.normal.iconColor = gray
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: gray]

        // Selected tab label: mint, matching the sticker world (tab content keeps AppColors.accent).
        let accent = UIColor(red: 0.482, green: 0.89, blue: 0.776, alpha: 1)
        appearance.stackedLayoutAppearance.selected.iconColor = accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        appearance.inlineLayoutAppearance.selected.iconColor = accent
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        appearance.compactInlineLayoutAppearance.selected.iconColor = accent
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(
            try! ModelContainer(
                for: User.self, Exercise.self, SpacedRepetitionCard.self,
                     DailySession.self, BrainScoreResult.self, Achievement.self,
                configurations: ModelConfiguration(cloudKitDatabase: .none)
            )
        )
    }
}

// MARK: - AppDelegate (notification handling)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Handle notification tap — convert deep link in userInfo to URL open
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            let notificationType = response.notification.request.content.categoryIdentifier.isEmpty
                ? response.notification.request.identifier.components(separatedBy: "_").first ?? "unknown"
                : response.notification.request.content.categoryIdentifier
            Analytics.appOpenedFromNotification(notificationType: notificationType)
            // Route directly instead of UIApplication.shared.open(url): opening
            // our own custom scheme back into the same app drops the link on
            // cold launch and lands on home. PendingDeepLink posts to a live
            // listener and stashes for cold-launch drain.
            PendingDeepLink.route(url)
        }
        completionHandler()
    }

    /// Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
