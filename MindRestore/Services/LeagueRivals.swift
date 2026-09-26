import Foundation

/// Labeled bot rivals that keep a sparse league competitive. They fill a board up to
/// `minimumBoard` entries, paced around the player's score from the start of the day:
/// one or two just ahead to chase, one or two just behind. Real players always replace them.
enum LeagueRivals {
    static let names = ["Byte", "Pixel", "Turbo", "Nova"]
    static let minimumBoard = 5

    static func board(
        real: [LeaderboardEntryData],
        category: LeaderboardCategory,
        baseline: Int?,
        day: Date,
        calendar: Calendar = .current
    ) -> [LeaderboardEntryData] {
        let needed = min(names.count, max(0, minimumBoard - real.count))
        let lowerIsBetter = category.lowerIsBetter
        let dayIndex = Int(calendar.startOfDay(for: day).timeIntervalSince1970 / 86_400)
        let base = max(baseline ?? defaultBaseline(for: category), lowerIsBetter ? 150 : 2)

        // Slots in fill order: just ahead, just behind, further ahead, further behind.
        let factors: [Double] = lowerIsBetter ? [0.92, 1.10, 0.80, 1.30] : [1.12, 0.88, 1.30, 0.70]
        var rivals: [LeaderboardEntryData] = []
        var lastAhead = base, lastBehind = base
        for slot in 0..<needed {
            let jitter = 1 + (seeded(dayIndex, slot) - 0.5) * 0.06
            let raw = Int((Double(base) * factors[slot] * jitter).rounded())
            let isAhead = slot % 2 == 0
            let score: Int
            if isAhead {
                // Ahead means strictly better than the last ahead-rival (and than the baseline).
                score = lowerIsBetter ? min(lastAhead - 1, raw) : max(lastAhead + 1, raw)
                lastAhead = score
            } else {
                score = lowerIsBetter ? max(lastBehind + 1, raw) : min(lastBehind - 1, raw)
                lastBehind = score
            }
            guard score > 0 else { continue }
            let name = names[(slot + dayIndex) % names.count]
            rivals.append(LeaderboardEntryData(rank: 0, username: name, score: score, avatarEmoji: "", level: 0, isCurrentUser: false, isRival: true))
        }

        let merged = (real + rivals).enumerated().sorted { a, b in
            if a.element.score != b.element.score {
                return lowerIsBetter ? a.element.score < b.element.score : a.element.score > b.element.score
            }
            if a.element.isRival != b.element.isRival { return !a.element.isRival }   // ties go to real players
            return a.offset < b.offset
        }
        return merged.enumerated().map { index, pair in
            let e = pair.element
            return LeaderboardEntryData(rank: index + 1, username: e.username, score: e.score, avatarEmoji: e.avatarEmoji,
                                        level: e.level, isCurrentUser: e.isCurrentUser, isRival: e.isRival)
        }
    }

    /// A starting level for boards where the player has no score yet.
    static func defaultBaseline(for category: LeaderboardCategory) -> Int {
        switch category {
        case .focusBlocking: return 45
        case .streak: return 3
        case .reactionTime: return 380
        case .visualMemory: return 7
        case .numberMemory: return 7
        case .chimpTest: return 8
        case .mathSprint: return 12
        case .colorMatch: return 14
        }
    }

    private static func seeded(_ day: Int, _ slot: Int) -> Double {
        let v = sin(Double(day) * 12.9898 + Double(slot) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }
}

/// The player's score at the first look of the day, per board. Rivals pace off it,
/// so improving later in the day passes them; tomorrow they re-pace.
enum LeagueRivalMemory {
    static func baseline(
        category: LeaderboardCategory,
        filter: LeaderboardTimeFilter,
        userScore: Int?,
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar = .current
    ) -> Int? {
        let key = "league_rival_baseline_\(category.rawValue)_\(filter.rawValue)"
        let day = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        if let stored = defaults.array(forKey: key) as? [Int], stored.count == 2, stored[0] == day {
            return stored[1]
        }
        guard let userScore, userScore > 0 else { return nil }
        defaults.set([day, userScore], forKey: key)
        return userScore
    }
}

/// The onboarding demo's board when Game Center can't give one: Memo's labeled
/// practice rivals placed around the level the user just reached, so the climb
/// always passes a few of them and there's always one left to chase.
enum OnboardingRivals {
    private static let seats: [(name: String, offset: Int)] = [("Byte", 2), ("Turbo", -1), ("Pixel", -2), ("Nova", -3)]

    static func entries(level: Int) -> [LeaderboardEntryData] {
        guard level > 0 else { return [] }
        return seats
            .map { (name: $0.name, score: level + $0.offset) }
            .filter { $0.score >= 1 }
            .enumerated()
            .map { index, seat in
                var entry = LeaderboardEntryData(rank: index + 1, username: seat.name, score: seat.score, avatarEmoji: "", level: seat.score, isCurrentUser: false)
                entry.isRival = true
                return entry
            }
    }
}
