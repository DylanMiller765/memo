import SwiftUI

/// End of a Train-tab game. Same inputs every game already passes; renders the
/// score line and this week's board (GameResultScreen).
struct GameResultView: View {
    // Required
    let gameTitle: String
    let gameIcon: String
    let accentColor: Color
    let mainScore: Int
    let scoreLabel: String  // e.g. "LEVEL REACHED", "MILLISECONDS", "% ACCURACY"
    let ratingText: String  // e.g. "Good Job!", "Lightning Fast!"
    let stats: [(label: String, value: String)]

    // Optional
    var isNewPersonalBest: Bool = false
    var personalBest: Int = 0
    var exerciseType: ExerciseType? = nil
    var leaderboardScore: Int = 0
    var confettiColors: [Color] = []
    var emoji: String? = nil
    var subtitleText: String? = nil

    // Callbacks
    var onPlayAgain: () -> Void
    var onDone: () -> Void

    private var game: UnlockGame? { exerciseType.flatMap(UnlockGame.init(exerciseType:)) }

    var body: some View {
        LiveGameEnd(game: game) { board, signIn in
            if let game {
                GameResultScreen(
                    summary: GameResultSummary(game: game, score: leaderboardScore > 0 ? leaderboardScore : mainScore,
                                               isNewBest: isNewPersonalBest),
                    board: board, onSignIn: signIn, onPlayAgain: onPlayAgain, onDone: onDone
                )
            }
        }
    }
}
