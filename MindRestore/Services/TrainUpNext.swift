import Foundation

/// Which game the Train tab suggests next: the first one (in catalog order) you haven't
/// played today; once you've played them all, the one you played longest ago.
enum TrainUpNext {
    static func pick(games: [ExerciseType], playedToday: Set<ExerciseType>, lastPlayed: [ExerciseType: Date]) -> ExerciseType? {
        if let fresh = games.first(where: { !playedToday.contains($0) }) { return fresh }
        return games.min { (lastPlayed[$0] ?? .distantPast) < (lastPlayed[$1] ?? .distantPast) }
    }
}
