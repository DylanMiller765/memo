#if DEBUG
import SwiftUI

// Screenshot hosts for GameResultScreen with sample data:
//   flow-normal (signed in), flow-pb (new best, signed in), flow-out (signed out: Memo's rivals), flow-zero (no score)

struct ResultMockScreen: View {
    let target: String

    private static let entries: [LeaderboardEntryData] = [
        ("maya.k", 14), ("jdub", 12), ("alexr", 11), ("sam_t", 10), ("k.lee", 8), ("nora", 7), ("theo", 6), ("zz", 5),
    ].enumerated().map { i, p in
        LeaderboardEntryData(rank: i + 1, username: p.0, score: p.1, avatarEmoji: "", level: 0, isCurrentUser: false)
    }

    var body: some View {
        let pb = target == "flow-pb"
        ZStack {
            GameBackdrop(glow: Color(red: 0.17, green: 0.23, blue: 0.53))
            GameResultScreen(
                summary: GameResultSummary(game: .visualMemory, score: target == "flow-zero" ? 0 : 9, isNewBest: pb),
                board: target == "flow-out" ? .practice : .loaded(entries: Self.entries, totalPlayers: 214),
                onPlayAgain: {}, onDone: {}
            )
        }
    }
}
#endif
