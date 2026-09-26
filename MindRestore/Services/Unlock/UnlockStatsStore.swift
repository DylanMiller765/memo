import Foundation

struct UnlockWeekStats: Equatable {
    var earned = 0
    var earnedMinutes = 0
    var denied = 0
    var resisted = 0
}

/// Per-day unlock outcomes in the app group, for Insights: unlocks earned by
/// playing (and their minutes), runs denied, and "Stay off" taps. FREE PASS
/// and the escape hatch aren't earned, so they aren't counted here.
final class UnlockStatsStore {
    static let shared = UnlockStatsStore(defaults: UserDefaults(suiteName: "group.com.memori.shared") ?? .standard)
    static let key = "unlock_stats_by_day"
    private static let keepDays = 14

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    func recordEarned(minutes: Int) {
        update { $0["earned", default: 0] += 1; $0["earnedMinutes", default: 0] += minutes }
    }

    func recordDenied() { update { $0["denied", default: 0] += 1 } }

    func recordResisted() { update { $0["resisted", default: 0] += 1 } }

    /// Totals for the current calendar week (the same week Focus minutes use).
    func thisWeek() -> UnlockWeekStats {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now()) else { return UnlockWeekStats() }
        var stats = UnlockWeekStats()
        for (stamp, day) in stored() {
            guard let date = date(from: stamp), week.contains(date) else { continue }
            stats.earned += day["earned"] ?? 0
            stats.earnedMinutes += day["earnedMinutes"] ?? 0
            stats.denied += day["denied"] ?? 0
            stats.resisted += day["resisted"] ?? 0
        }
        return stats
    }

    // MARK: Storage

    private func update(_ change: (inout [String: Int]) -> Void) {
        var all = stored()
        let today = stamp(for: now())
        var day = all[today] ?? [:]
        change(&day)
        all[today] = day
        let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: calendar.startOfDay(for: now())) ?? .distantPast
        all = all.filter { (date(from: $0.key) ?? .distantPast) > cutoff }
        defaults.set(all, forKey: Self.key)
    }

    private func stored() -> [String: [String: Int]] {
        (defaults.dictionary(forKey: Self.key) as? [String: [String: Int]]) ?? [:]
    }

    private func stamp(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func date(from stamp: String) -> Date? {
        let parts = stamp.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
