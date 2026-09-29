import Foundation

/// What "Reset All Data" clears besides the SwiftData models: saved counters,
/// first-run flags and the booth's pending spin. Subscription, onboarding and
/// the once-a-day free pass are left alone.
enum ProgressReset {
    static let standardPrefixes = ["exercise.hasPlayed.", "home_charge_", "league_rival_baseline_"]
    static let standardKeys = ["lastCelebratedStreak", "training_exercise_count", "training_exercise_date",
                               ReviewPromptService.unlocksEarnedKey]
    static let sharedKeys = ["unlock_stats_by_day", "unlock_pending_spin"]

    static func clear(standard: UserDefaults, shared: UserDefaults) {
        for key in standard.dictionaryRepresentation().keys
        where standardPrefixes.contains(where: key.hasPrefix) || standardKeys.contains(key) {
            standard.removeObject(forKey: key)
        }
        for key in sharedKeys { shared.removeObject(forKey: key) }
    }
}
