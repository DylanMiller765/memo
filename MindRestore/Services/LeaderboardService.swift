import Foundation

// MARK: - Enums

enum LeaderboardCategory: String, CaseIterable, Identifiable {
    // Per-game v2 boards, in Train-tab order
    case visualMemory = "Visual Memory"
    case numberMemory = "Number Memory"
    case chimpTest = "Chimp Test"
    case mathSprint = "Math Sprint"
    case colorMatch = "Color Match"
    case reactionTime = "Reaction Time"
    case streak = "Streak"
    case focusBlocking = "Focus Mode"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .visualMemory: return "square.grid.3x3.fill"
        case .numberMemory: return "number"
        case .chimpTest: return "pawprint.fill"
        case .mathSprint: return "multiply"
        case .colorMatch: return "paintpalette.fill"
        case .reactionTime: return "bolt.fill"
        case .streak: return "flame.fill"
        case .focusBlocking: return "shield.slash.fill"
        }
    }

    var scoreDescription: String {
        switch self {
        case .visualMemory: return "Highest grid level completed"
        case .numberMemory: return "Longest number recalled, in digits"
        case .chimpTest: return "Most numbers in a completed level"
        case .mathSprint: return "Most questions answered before the bar runs out"
        case .colorMatch: return "Most correct before the bar runs out"
        case .reactionTime: return "Fastest 5-round average — lower is better"
        case .streak: return "Longest consecutive days trained"
        case .focusBlocking: return "Protected Focus Mode time. More ranks higher."
        }
    }

    /// Reaction Time sorts ascending (ms); every other board is higher-is-better.
    var lowerIsBetter: Bool { self == .reactionTime }
}

enum LeaderboardTimeFilter: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case thisWeek = "This week"
    case allTime = "All time"

    var id: String { rawValue }
}

// MARK: - Display Data

struct LeaderboardEntryData: Identifiable, Sendable {
    let id = UUID()
    let rank: Int
    let username: String
    let score: Int
    let avatarEmoji: String
    let level: Int
    let isCurrentUser: Bool
}
