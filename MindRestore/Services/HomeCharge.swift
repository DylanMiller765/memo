import Foundation

/// How Memo's world looks today. Rain = no games today and the last session was 2+ days ago.
enum HomeTier: Equatable { case rain(days: Int), dim, calm, glow }

/// Today's charge on Home: 3 games = 100%.
struct HomeCharge: Equatable {
    let gamesToday: Int
    let percent: Int
    let tier: HomeTier
    let mood: MascotRiveMood
    let line: String

    static func make(gamesToday: Int, lastSessionDate: Date?, now: Date, calendar: Calendar = .current) -> HomeCharge {
        let games = min(max(gamesToday, 0), 3)
        let percent = [0, 33, 67, 100][games]
        var tier: HomeTier
        switch games {
        case 3: tier = .glow
        case 2: tier = .calm
        default: tier = .dim
        }
        if games == 0, let last = lastSessionDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
            if days >= 2 { tier = .rain(days: days) }
        }
        let mood: MascotRiveMood
        switch tier { case .glow: mood = .happy; case .rain: mood = .sad; default: mood = .neutral }
        let line: String
        switch tier {
        case .glow: line = "Fully charged. See you tomorrow."
        case .calm: line = "1 more game for 100%."
        case .dim: line = "\(3 - games) more games to charge Memo up."
        case .rain(let days): line = "Memo's been rained on for \(days) \(days == 1 ? "day" : "days"). Play 1 game."
        }
        return HomeCharge(gamesToday: games, percent: percent, tier: tier, mood: mood, line: line)
    }
}

/// Remembers the last charge Home showed today so the count-up payoff plays once per increase.
enum HomeChargeMemory {
    static let dayKey = "home_charge_seen_day"
    static let valueKey = "home_charge_seen_value"

    /// Returns the percent to animate FROM (nil = no payoff) and stores `current` for today.
    static func payoffStart(current: Int, now: Date, defaults: UserDefaults, calendar: Calendar = .current) -> Int? {
        let day = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        defer { defaults.set(day, forKey: dayKey); defaults.set(current, forKey: valueKey) }
        guard defaults.integer(forKey: dayKey) == day, defaults.object(forKey: valueKey) != nil else { return nil }
        let seen = defaults.integer(forKey: valueKey)
        return current > seen ? seen : nil
    }
}
