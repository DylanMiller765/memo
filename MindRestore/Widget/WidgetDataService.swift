import Foundation
import WidgetKit

/// Bridges the main app's data to the widget via shared UserDefaults.
/// Configure the App Group "group.com.memori.shared" in Xcode for both
/// the main target and the widget extension target.
enum WidgetDataService {

    static let suiteName = "group.com.memori.shared"

    // MARK: - Keys

    private enum Key {
        static let streak       = "widget_streak"
        static let exercisesToday = "widget_exercisesToday"
        static let trainedToday = "widget_trainedToday"
        static let lastUpdated  = "widget_lastUpdated"
    }

    // MARK: - Write (called from main app)

    static func updateWidgetData(streak: Int, exercisesToday: Int, trainedToday: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(streak, forKey: Key.streak)
        defaults.set(exercisesToday, forKey: Key.exercisesToday)
        defaults.set(trainedToday, forKey: Key.trainedToday)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastUpdated)

        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read (used by widget timeline provider)

    struct Snapshot {
        var streak: Int
        var exercisesToday: Int
        var trainedToday: Bool
    }

    static func currentSnapshot() -> Snapshot {
        let defaults = UserDefaults(suiteName: suiteName)
        return Snapshot(
            streak: defaults?.integer(forKey: Key.streak) ?? 0,
            exercisesToday: defaults?.integer(forKey: Key.exercisesToday) ?? 0,
            trainedToday: defaults?.bool(forKey: Key.trainedToday) ?? false
        )
    }
}
