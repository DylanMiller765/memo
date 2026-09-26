import Foundation

/// The "who's next" line on your rank card: how much you need to pass the player above you
/// (or how far ahead you are at #1), plus progress toward them for the chase bar.
struct LeagueChase: Equatable {
    let text: String
    /// 0...1, how close you are to the next player (1 when you're #1).
    let progress: Double
    /// The rank you're chasing; nil when you're #1.
    let nextRank: Int?

    static func make(category: LeaderboardCategory, entries: [LeaderboardEntryData]) -> LeagueChase? {
        guard let me = entries.first(where: { $0.isCurrentUser }) else { return nil }
        let lowerIsBetter = category.lowerIsBetter

        if me.rank == 1 {
            guard let second = entries.first(where: { $0.rank == 2 }) else {
                return LeagueChase(text: "Holding #1", progress: 1, nextRank: nil)
            }
            let lead = max(0, lowerIsBetter ? second.score - me.score : me.score - second.score)
            let amount = lowerIsBetter ? "\(lead) ms" : amountText(lead, category: category)
            return LeagueChase(text: "\(amount) ahead of \(second.username)", progress: 1, nextRank: nil)
        }

        guard let next = entries.first(where: { $0.rank == me.rank - 1 }) else { return nil }
        // Ties don't pass, so you need one more unit than the gap.
        let gap = max(0, lowerIsBetter ? me.score - next.score : next.score - me.score) + 1
        let progress: Double
        if lowerIsBetter {
            progress = me.score > 0 ? Double(next.score) / Double(me.score) : 0
        } else {
            progress = next.score > 0 ? Double(me.score) / Double(next.score) : 0
        }
        return LeagueChase(
            text: "\(amountText(gap, category: category)) to pass \(next.username)",
            progress: min(max(progress, 0), 1),
            nextRank: next.rank
        )
    }

    private static func amountText(_ n: Int, category: LeaderboardCategory) -> String {
        func plural(_ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        switch category {
        case .focusBlocking:
            return n >= 60 ? String(format: "%dh %02dm", n / 60, n % 60) : "\(n)m"
        case .streak: return plural("day")
        case .reactionTime: return "\(n) ms faster"
        case .visualMemory: return plural("level")
        case .numberMemory: return plural("digit")
        case .chimpTest: return plural("number")
        case .mathSprint, .colorMatch: return "\(n) more"
        }
    }
}
