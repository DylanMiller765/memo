import Foundation

enum UnlockGame: String, CaseIterable, Codable, Sendable {
    case visualMemory, numberMemory, chimpTest, mathSprint, colorMatch, reactionTime

    var exerciseType: ExerciseType {
        switch self {
        case .visualMemory: .visualMemory
        case .numberMemory: .sequentialMemory
        case .chimpTest: .chimpTest
        case .mathSprint: .mathSpeed
        case .colorMatch: .colorMatch
        case .reactionTime: .reactionTime
        }
    }

    init?(exerciseType: ExerciseType) {
        guard let match = Self.allCases.first(where: { $0.exerciseType == exerciseType }) else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .visualMemory: "Visual Memory"
        case .numberMemory: "Number Memory"
        case .chimpTest: "Chimp Test"
        case .mathSprint: "Math Sprint"
        case .colorMatch: "Color Match"
        case .reactionTime: "Reaction Time"
        }
    }

    var passLineText: String {
        switch self {
        case .visualMemory: "reach LV 4"
        case .numberMemory: "6 digits"
        case .chimpTest: "5 numbers"
        case .mathSprint: "8 correct"
        case .colorMatch: "10 correct"
        case .reactionTime: "avg ≤ 400ms"
        }
    }

    var isEndless: Bool { self != .reactionTime }
    var lowerIsBetter: Bool { self == .reactionTime }
}

enum UnlockTier: Int, Comparable, Codable, Sendable {
    case none = 0, pass, great, elite
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var next: UnlockTier? { UnlockTier(rawValue: rawValue + 1) }
}

struct BannerProgress: Equatable {
    let filled: Int
    let total: Int
    let targetTier: UnlockTier
    let isMaxed: Bool
}

enum UnlockRulebook {
    static let personalBestBonus = 2
    static let freePassMinutes = 10
    static let escapeHatchMinutes = 2
    static let escapeHatchCountdownSeconds = 15
    static let escapeHatchAfterDenials = 2
    static let pendingSpinLifetime: TimeInterval = 30 * 60
    static let freePassWeight = 0.085
    static let reactionRounds = 5

    private static let table: [UnlockGame: (pass: Int, great: Int, elite: Int)] = [
        .visualMemory: (4, 7, 10),
        .numberMemory: (6, 8, 10),
        .chimpTest: (5, 8, 11),
        .mathSprint: (8, 14, 20),
        .colorMatch: (10, 18, 26),
        .reactionTime: (400, 320, 270),
    ]

    static func threshold(_ tier: UnlockTier, for game: UnlockGame) -> Int {
        let row = table[game]!
        switch tier {
        case .none: return game.lowerIsBetter ? Int.max : 0
        case .pass: return row.pass
        case .great: return row.great
        case .elite: return row.elite
        }
    }

    static func tier(for game: UnlockGame, score: Int) -> UnlockTier {
        if game.lowerIsBetter && score <= 0 { return .none }
        for candidate in [UnlockTier.elite, .great, .pass] {
            let bar = threshold(candidate, for: game)
            if game.lowerIsBetter ? score <= bar : score >= bar { return candidate }
        }
        return .none
    }

    static func minutes(for tier: UnlockTier, isPersonalBest: Bool) -> Int {
        let base: Int
        switch tier {
        case .none: return 0
        case .pass: base = 5
        case .great: base = 10
        case .elite: base = 15
        }
        return base + (isPersonalBest ? personalBestBonus : 0)
    }

    static func isPersonalBest(game: UnlockGame, score: Int, previousBest: Int) -> Bool {
        guard score > 0 else { return false }
        guard previousBest > 0 else { return true }
        return game.lowerIsBetter ? score < previousBest : score > previousBest
    }

    static func distanceToPass(game: UnlockGame, score: Int) -> Int {
        let pass = threshold(.pass, for: game)
        return game.lowerIsBetter ? max(0, score - pass) : max(0, pass - score)
    }

    static func bannerProgress(game: UnlockGame, score: Int, roundsPlayed: Int) -> BannerProgress {
        if !game.isEndless {
            return BannerProgress(filled: min(roundsPlayed, reactionRounds), total: reactionRounds,
                                  targetTier: .pass, isMaxed: false)
        }
        let current = tier(for: game, score: score)
        guard let target = current.next else {
            return BannerProgress(filled: 1, total: 1, targetTier: .elite, isMaxed: true)
        }
        let floor = threshold(current, for: game)
        let ceiling = threshold(target, for: game)
        let total = max(1, ceiling - floor)
        return BannerProgress(filled: max(0, min(total, score - floor)), total: total,
                              targetTier: target, isMaxed: false)
    }
}
