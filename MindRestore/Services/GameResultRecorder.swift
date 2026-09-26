import Foundation
import SwiftData

/// One place that records a finished game: saves the Exercise, bumps today's
/// session and the streak, refreshes the widget, reports the game's
/// leaderboard, and posts `.workoutGameCompleted`.
enum GameResultRecorder {
    @MainActor
    static func record(
        type: ExerciseType,
        accuracy: Double,
        difficulty: Int,
        durationSeconds: Int,
        leaderboardScore: Int,
        user: User?,
        modelContext: ModelContext,
        gameCenter: GameCenterService
    ) {
        let exercise = Exercise(type: type, difficulty: difficulty, score: accuracy, durationSeconds: durationSeconds)
        modelContext.insert(exercise)

        let descriptor = FetchDescriptor<DailySession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let session: DailySession
        if let today = sessions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            session = today
        } else {
            session = DailySession()
            modelContext.insert(session)
        }
        session.addExercise(exercise)

        if let user {
            _ = user.updateStreak()
            user.totalExercises += 1
            NotificationService.shared.cancelStreakRisk()
            NotificationService.shared.scheduleMilestone(streak: user.currentStreak)
            WidgetDataService.updateWidgetData(
                streak: user.currentStreak,
                exercisesToday: session.exercisesCompleted.count,
                trainedToday: true
            )
            if !gameCenter.isAuthenticated, user.totalExercises == 1 { gameCenter.authenticate() }
            gameCenter.reportScore(user.longestStreak, leaderboardID: GameCenterService.longestStreakLeaderboard)
        }
        try? modelContext.save()

        if leaderboardScore > 0, let id = GameCenterService.gameLeaderboardID(for: type) {
            gameCenter.reportScore(leaderboardScore, leaderboardID: id)
        }
        Analytics.exerciseCompleted(game: type.rawValue, score: accuracy, difficulty: difficulty)

        if let user {
            ReviewPromptService.requestIfAppropriate(totalExercises: user.totalExercises, streak: user.currentStreak)
            let milestones = [7, 14, 30, 60, 100]
            let lastCelebrated = UserDefaults.standard.integer(forKey: "lastCelebratedStreak")
            if milestones.contains(user.currentStreak), lastCelebrated < user.currentStreak {
                UserDefaults.standard.set(user.currentStreak, forKey: "lastCelebratedStreak")
                Analytics.streakMilestone(streak: user.currentStreak)
                NotificationCenter.default.post(
                    name: .streakMilestoneCelebration,
                    object: nil,
                    userInfo: ["streak": user.currentStreak]
                )
            }
        }
        NotificationCenter.default.post(
            name: .workoutGameCompleted,
            object: nil,
            userInfo: ["exerciseType": type.rawValue, "score": accuracy, "leaderboardScore": leaderboardScore]
        )
    }
}
