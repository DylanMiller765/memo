import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastSessionDate: Date?
    var subscriptionStatusRaw: String = SubscriptionStatus.free.rawValue
    var trialStartDate: Date?
    var hasCompletedOnboarding: Bool = false
    var focusGoalsRaw: [String] = []
    var dailyGoal: Int = 3
    var notificationsEnabled: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var soundEnabled: Bool = true

    // Streak Freeze System
    var streakFreezes: Int = 1
    var streakFreezeUsedDate: Date?
    var streakFreezeLastAwardDate: Date?

    var maxStreakFreezes: Int { 2 }

    // XP & Level System
    var totalXP: Int = 0
    var level: Int = 1
    var username: String = ""
    var userAge: Int = 0  // 0 = not provided
    var avatarEmoji: String = ""
    var totalExercises: Int = 0
    var resistedCount: Int = 0
    var totalPerfectScores: Int = 0
    var hasShared: Bool = false

    init() {
        let emojis = ["🧠", "⚡️", "🔥", "💡", "🎯", "🌟", "🚀", "💪", "🏆", "🎓"]
        avatarEmoji = emojis.randomElement() ?? "🧠"
    }

    // NOTE: subscriptionStatus and isProUser are unused — StoreService.isProUser is the source of truth.
    // Kept for SwiftData schema compatibility.
    var subscriptionStatus: SubscriptionStatus {
        get { SubscriptionStatus(rawValue: subscriptionStatusRaw) ?? .free }
        set { subscriptionStatusRaw = newValue.rawValue }
    }

    var focusGoals: [UserFocusGoal] {
        get { focusGoalsRaw.compactMap { UserFocusGoal(rawValue: $0) } }
        set { focusGoalsRaw = newValue.map(\.rawValue) }
    }

    // NOTE: Unused — StoreService.isProUser is the source of truth.
    var isProUser: Bool {
        subscriptionStatus == .subscribed || subscriptionStatus == .trial
    }

    /// Updates the streak for the given date. Returns a `StreakFreezeEvent` describing
    /// whether a freeze was consumed or earned, so callers can show appropriate UI.
    @discardableResult
    func updateStreak(on date: Date = .now) -> StreakFreezeEvent {
        let calendar = Calendar.current
        var event = StreakFreezeEvent()

        if let last = lastSessionDate {
            if calendar.isDate(last, inSameDayAs: date) {
                // Already trained today — check if a freeze should be awarded
                event.freezeEarned = checkAndAwardStreakFreeze(on: date)
                return event
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
                      calendar.isDate(last, inSameDayAs: yesterday) {
                // Trained yesterday — streak continues normally
                currentStreak += 1
            } else {
                // Missed at least one day — attempt to use a streak freeze
                if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
                   streakFreezes > 0 {
                    // Use a freeze for yesterday
                    streakFreezes -= 1
                    streakFreezeUsedDate = yesterday
                    currentStreak += 1
                    event.freezeUsed = true
                    event.savedStreak = currentStreak
                } else {
                    // No freezes available — streak resets
                    currentStreak = 1
                }
            }
        } else {
            currentStreak = 1
        }

        lastSessionDate = date
        longestStreak = max(longestStreak, currentStreak)
        event.freezeEarned = checkAndAwardStreakFreeze(on: date)
        return event
    }

    /// Awards a streak freeze every 7 consecutive days (max `maxStreakFreezes`).
    /// Returns `true` if a freeze was just earned.
    private func checkAndAwardStreakFreeze(on date: Date) -> Bool {
        let calendar = Calendar.current
        guard currentStreak > 0, currentStreak.isMultiple(of: 7) else { return false }
        guard streakFreezes < maxStreakFreezes else { return false }

        // Prevent awarding twice for the same milestone
        if let lastAward = streakFreezeLastAwardDate,
           calendar.isDate(lastAward, inSameDayAs: date) {
            return false
        }

        streakFreezes += 1
        streakFreezeLastAwardDate = date
        return true
    }

    var isStreakActive: Bool {
        guard let last = lastSessionDate else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(last) || calendar.isDateInYesterday(last)
    }

    // MARK: - XP & Level

    var xpForNextLevel: Int {
        UserLevel.xpRequired(for: level + 1)
    }

    var xpProgress: Double {
        let currentLevelXP = UserLevel.xpRequired(for: level)
        let nextLevelXP = UserLevel.xpRequired(for: level + 1)
        let range = nextLevelXP - currentLevelXP
        guard range > 0 else { return 1.0 }
        return min(1.0, max(0.0, Double(totalXP - currentLevelXP) / Double(range)))
    }

    var levelName: String {
        UserLevel.name(for: level)
    }

    @discardableResult
    func addXP(_ amount: Int) -> Bool {
        totalXP += amount
        let newLevel = UserLevel.level(for: totalXP)
        if newLevel > level {
            level = newLevel
            return true // leveled up
        }
        return false
    }

    func xpForExercise(score: Double, difficulty: Int) -> Int {
        let base = 50
        let scoreBonus = Int(score * 100)
        let difficultyMultiplier = max(1, difficulty)
        let streakBonus = min(currentStreak * 5, 50)
        return (base + scoreBonus) * difficultyMultiplier + streakBonus
    }
}

// MARK: - Streak Freeze Event

/// Describes what happened with streak freezes during a streak update.
struct StreakFreezeEvent {
    /// A freeze was auto-used to save the streak.
    var freezeUsed: Bool = false
    /// The streak value that was saved (only meaningful when `freezeUsed` is true).
    var savedStreak: Int = 0
    /// A new streak freeze was earned on this update.
    var freezeEarned: Bool = false
}
