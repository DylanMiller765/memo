import Foundation
import UserNotifications

final class NotificationService: Sendable {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Daily Reminder

    private static let reminderMessages: [(title: String, body: String)] = [
        ("Memo is on patrol", "Run 3 quick rounds, then close the app before the feed gets loud."),
        ("Train before the feed wins", "A few reps now makes the next scroll harder to justify."),
        ("Put the feed on notice", "Train memory, speed, or attention. Then get back to your day."),
        ("Memo needs 3 reps", "Quick session in, phone down after. That's the whole move."),
        ("Guard the next unlock", "Train now so Memo has something to push back with later."),
        ("The feed can wait", "One fast workout. Then leave Memo and do the real thing."),
        ("Your brain gets first dibs", "Train before TikTok, Instagram, or YouTube gets the opening bid."),
        ("Lock in today's reps", "3 games keeps Memo sharp without turning into another app spiral."),
        ("Memo is still guarding", "Give it a quick training receipt, then get off your phone."),
        ("Tiny workout, real pushback", "A few minutes of training makes the feed less automatic."),
    ]

    func scheduleDailyReminder(hour: Int, minute: Int, streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let message = Self.reminderMessages[dayOfYear % Self.reminderMessages.count]

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = streak > 0
            ? "\(message.body) \(streak)-day streak on deck."
            : message.body
        content.sound = .default
        content.userInfo = ["deepLink": "memo://train"]

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)

        center.add(request)
    }

    // MARK: - Streak Risk

    private static func streakRiskMessages(streak: Int) -> [(title: String, body: String)] {
        [
            ("Streak on the line", "One game keeps your \(streak)-day training streak alive before midnight."),
            ("Protect the streak", "\(streak) days of reps. One quick round keeps it moving."),
            ("Last call for today's rep", "Train once before midnight and Memo keeps the streak receipt."),
            ("Do the tiny hard thing", "One game saves the \(streak)-day streak. Then get off the app."),
            ("The feed would love a miss", "One training round keeps your \(streak)-day streak out of its hands."),
        ]
    }

    func scheduleStreakRisk(streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak_risk"])

        guard streak > 0 else { return }

        let messages = Self.streakRiskMessages(streak: streak)
        let message = messages[streak % messages.count]

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.userInfo = ["deepLink": "memo://train"]

        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "streak_risk", content: content, trigger: trigger)

        center.add(request)
    }

    // MARK: - Milestones

    func scheduleMilestone(streak: Int) {
        let milestones = [3, 7, 14, 30, 60, 100]
        guard milestones.contains(streak) else { return }

        let messages: [Int: (title: String, body: String)] = [
            3: ("3 days on patrol", "Memo has a real training streak now. Keep the feed earning its way back."),
            7: ("One week guarded", "7 straight days of reps. The feed had to work harder this week."),
            14: ("Two weeks of pushback", "14 days of training before the scroll. That is the system working."),
            30: ("30 days trained", "A full month of putting your brain before the feed."),
            60: ("60 days guarded", "Two months of reps, locks, and comeback receipts."),
            100: ("100 days of Memo", "Triple digits. The feed is no longer driving without a fight."),
        ]

        let message = messages[streak] ?? ("\(streak) days trained", "Memo logged another streak milestone.")

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.userInfo = ["deepLink": "memo://train"]

        // Fire as a next-morning re-engagement, not a banner stacked on top of the
        // in-app celebration the user just saw the moment they hit the milestone.
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date.now),
              let fireDate = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) else { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: "milestone_\(streak)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Comeback Notifications

    func scheduleComebackNotification(lastTrainedDaysAgo: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["comeback"])

        guard lastTrainedDaysAgo >= 2 else { return }

        let messages: [(title: String, body: String)] = [
            ("The feed got comfortable", "\(lastTrainedDaysAgo) days without a rep. One game puts Memo back on patrol."),
            ("Memo needs a fresh receipt", "Train once today so the next unlock is earned, not automatic."),
            ("Comeback round", "\(lastTrainedDaysAgo) days off. Start with one fast game and leave."),
            ("Reset the pattern", "The scroll had \(lastTrainedDaysAgo) quiet days. Memo only needs one rep to push back."),
        ]

        let message = messages[lastTrainedDaysAgo % messages.count]

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.userInfo = ["deepLink": "memo://train"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(identifier: "comeback", content: content, trigger: trigger)

        center.add(request)
    }

    // MARK: - Achievement Nudge

    func scheduleAchievementNudge(achievementName: String, progress: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement almost unlocked"
        content.body = "\(progress) to earn \"\(achievementName)\". One more receipt for Memo."
        content.sound = .default
        content.userInfo = ["deepLink": "memo://train"]

        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "achievement_nudge", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Retake Assessment Reminder

    private static let retakeIdentifier = "retake-reminder"

    func scheduleRetakeReminder(lastAssessmentDate: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.retakeIdentifier])

        guard let fireDate = Calendar.current.date(byAdding: .day, value: 7, to: lastAssessmentDate),
              fireDate > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Retake your Brain Score"
        content.body = "Memo has new training receipts. Check what changed."
        content.sound = .default
        content.userInfo = ["deepLink": "memo://insights"]

        let interval = fireDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(identifier: Self.retakeIdentifier, content: content, trigger: trigger)

        center.add(request)
    }

    func cancelRetakeReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.retakeIdentifier])
    }

    // MARK: - Trial Reminders

    static func trialReminderTitle(daysBefore: Int) -> String {
        "Your Memo trial ends in \(daysBefore) \(daysBefore == 1 ? "day" : "days")"
    }
    static let trialReminderBody = "Keep Memo guarding the feed, or cancel anytime in App Store."

    private static let trialEndDateKey = "memo_trial_end_date"
    private static let trialReminderPreferenceKey = "memo_trial_reminder_days_before"
    private static let trialReminderIdentifiers = [
        "trial_reminder_day5",
        "trial_reminder_last_day",
        "trial_reminder_selected"
    ]

    static var selectedTrialReminderDaysBefore: Int {
        UserDefaults.standard.integer(forKey: trialReminderPreferenceKey) == 1 ? 1 : 2
    }

    var hasUpcomingTrialReminder: Bool {
        guard let endDate = UserDefaults.standard.object(forKey: Self.trialEndDateKey) as? Date else {
            return false
        }
        return endDate > Date.now
    }

    func setTrialReminderDaysBefore(_ days: Int) {
        UserDefaults.standard.set(days == 1 ? 1 : 2, forKey: Self.trialReminderPreferenceKey)
        scheduleStoredTrialRemindersIfAuthorized()
    }

    func recordTrialStarted(endDate: Date) {
        guard endDate > Date.now else { return }
        UserDefaults.standard.set(endDate, forKey: Self.trialEndDateKey)
        scheduleStoredTrialRemindersIfAuthorized()
    }

    func scheduleStoredTrialRemindersIfAuthorized() {
        guard let endDate = UserDefaults.standard.object(forKey: Self.trialEndDateKey) as? Date,
              endDate > Date.now else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional ||
                  settings.authorizationStatus == .ephemeral else { return }

            scheduleTrialReminders(endDate: endDate)
        }
    }

    private func scheduleTrialReminders(endDate: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.trialReminderIdentifiers)

        let daysBefore = Self.selectedTrialReminderDaysBefore
        let fireDate = endDate.addingTimeInterval(-TimeInterval(daysBefore * 24 * 60 * 60))
        guard fireDate > Date.now else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.trialReminderTitle(daysBefore: daysBefore)
        content.body = Self.trialReminderBody
        content.sound = .default
        content.userInfo = ["deepLink": "memo://profile"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        let request = UNNotificationRequest(identifier: "trial_reminder_selected", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Brain Score Follow-Up


    func cancelStreakRisk() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["streak_risk"])
    }

    // MARK: - Weekly Leaderboard Reset Warning (Sunday 6pm — spaced off the 8pm streak-risk slot)

    func scheduleWeeklyLeaderboardReset() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly_leaderboard_reset"])

        let messages: [(String, String)] = [
            ("Leaderboard resets tonight", "One clean session before midnight. Then leave the app alone."),
            ("Final reps of the week", "Train once if you want the receipt on this week's board."),
            ("Week closes at midnight", "Memo can still log one more pushback before reset."),
        ]
        let pick = messages.randomElement()!

        let content = UNMutableNotificationContent()
        content.title = pick.0
        content.body = pick.1
        content.sound = .default
        content.userInfo = ["deepLink": "memo://compete"]

        // Sunday at 6pm, repeats weekly — kept off the 8pm streak-risk slot so the
        // two never fire back-to-back on Sunday evenings.
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday (Calendar.current's Sunday = 1)
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly_leaderboard_reset", content: content, trigger: trigger)
        center.add(request)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Identifiers the Notifications switch controls. The trial-ends reminder
    /// isn't one: the paywall promised it, so it stays until the trial is over.
    static let reminderIdentifiers = ["daily_reminder", "streak_risk", "comeback", "weekly_leaderboard_reset",
                                      "achievement_nudge", "retake-reminder"]

    static func isReminder(_ identifier: String) -> Bool {
        reminderIdentifiers.contains(identifier) || identifier.hasPrefix("milestone_")
    }

    /// Cancels Memo's reminders and milestone notes, and keeps the trial reminder.
    func cancelReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter(Self.isReminder)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
