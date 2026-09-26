import Foundation
import GameKit
import SwiftUI

@MainActor @Observable
final class GameCenterService {

    // MARK: - State

    var isAuthenticated = false
    private var hasInstalledAuthenticationHandler = false

    // MARK: - Leaderboard IDs

    // v2 boards (2.1.6): fresh boards for the new scoring — levels, digits,
    // numbers, correct answers and average ms. Game Center keeps the best score,
    // and the Compete tab reads them as This week / All time.
    static let visualMemoryLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.visualMemory"
    static let numberMemoryLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.numberMemory"
    static let chimpTestLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.chimpTest"
    static let mathSprintLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.mathSprint"
    static let colorMatchLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.colorMatch"
    static let reactionTimeLeaderboard = "com.dylanmiller.mindrestore.leaderboard.v2.reactionTime"
    static let longestStreakLeaderboard = "com.dylanmiller.mindrestore.leaderboard.longestStreak"
    static let focusBlockingLeaderboard = "com.dylanmiller.mindrestore.leaderboard.focusBlocking"
    static let focusBlockingDailyLeaderboard = "com.dylanmiller.mindrestore.leaderboard.focusBlocking.today"
    static let focusBlockingWeeklyLeaderboard = "com.dylanmiller.mindrestore.leaderboard.focusBlocking.weekly"

    /// Per-game leaderboard for the six active games; nil for everything else.
    static func gameLeaderboardID(for type: ExerciseType) -> String? {
        switch type {
        case .visualMemory: return visualMemoryLeaderboard
        case .sequentialMemory: return numberMemoryLeaderboard
        case .chimpTest: return chimpTestLeaderboard
        case .mathSpeed: return mathSprintLeaderboard
        case .colorMatch: return colorMatchLeaderboard
        case .reactionTime: return reactionTimeLeaderboard
        default: return nil
        }
    }

    /// Categories for the six active games, in Train-tab order.
    static let activeGameCategories: [LeaderboardCategory] = [
        .visualMemory, .numberMemory, .chimpTest, .mathSprint, .colorMatch, .reactionTime
    ]

    /// The local player's best (lowest) rank across the six game boards this week.
    func bestWeeklyRank() async -> Int? {
        guard isAuthenticated else { return nil }
        var best: Int?
        for category in Self.activeGameCategories {
            let result = await loadLeaderboardEntries(category: category, timeFilter: .thisWeek, range: NSRange(location: 1, length: 1))
            if let rank = result.localPlayerEntry?.rank, rank > 0 {
                best = min(best ?? rank, rank)
            }
        }
        return best
    }

    // MARK: - Achievement ID Mapping


    // MARK: - Category → Leaderboard ID

    static func leaderboardID(for category: LeaderboardCategory) -> String {
        switch category {
        case .visualMemory: return visualMemoryLeaderboard
        case .numberMemory: return numberMemoryLeaderboard
        case .chimpTest: return chimpTestLeaderboard
        case .mathSprint: return mathSprintLeaderboard
        case .colorMatch: return colorMatchLeaderboard
        case .reactionTime: return reactionTimeLeaderboard
        case .streak: return longestStreakLeaderboard
        case .focusBlocking: return focusBlockingLeaderboard
        }
    }

    static func leaderboardID(for category: LeaderboardCategory, timeFilter: LeaderboardTimeFilter) -> String {
        category == .focusBlocking ? focusLeaderboardID(for: timeFilter) : leaderboardID(for: category)
    }

    static func focusLeaderboardID(for timeFilter: LeaderboardTimeFilter) -> String {
        switch timeFilter {
        case .today:
            return focusBlockingDailyLeaderboard
        case .thisWeek, .allTime:
            return focusBlockingWeeklyLeaderboard
        }
    }

    private static func gameCenterTimeScope(
        for category: LeaderboardCategory,
        timeFilter: LeaderboardTimeFilter
    ) -> GKLeaderboard.TimeScope {
        switch timeFilter {
        case .today: return .today
        case .thisWeek: return .week
        case .allTime: return .allTime
        }
    }

    // MARK: - Authentication

    func authenticateIfNeeded() {
        guard !hasInstalledAuthenticationHandler else { return }
        hasInstalledAuthenticationHandler = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                if let viewController {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(viewController, animated: true)
                    }
                    return
                }

                if let error {
                    print("[GameCenterService] Authentication error: \(error.localizedDescription)")
                }

                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Compatibility alias for existing game-completion call sites. Installing
    /// the Game Center handler remains idempotent.
    func authenticate() {
        authenticateIfNeeded()
    }

    // MARK: - Load Leaderboard Entries

    struct LeaderboardResult {
        let entries: [LeaderboardEntryData]
        let localPlayerEntry: LeaderboardEntryData?
        let totalPlayerCount: Int
        var error: Error? = nil
    }

    func loadLeaderboardEntries(
        category: LeaderboardCategory,
        timeFilter: LeaderboardTimeFilter,
        range: NSRange = NSRange(location: 1, length: 50)
    ) async -> LeaderboardResult {
        guard isAuthenticated else {
            return LeaderboardResult(entries: [], localPlayerEntry: nil, totalPlayerCount: 0)
        }

        // Focus League uses distinct direct-minute leaderboards for Today and Week.
        let leaderboardID = Self.leaderboardID(for: category, timeFilter: timeFilter)
        let timeScope = Self.gameCenterTimeScope(for: category, timeFilter: timeFilter)

        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID])
            guard let leaderboard = leaderboards.first else {
                return LeaderboardResult(entries: [], localPlayerEntry: nil, totalPlayerCount: 0)
            }

            let (localEntry, globalEntries, totalCount) = try await leaderboard.loadEntries(
                for: .global,
                timeScope: timeScope,
                range: range
            )

            var entries: [LeaderboardEntryData] = []
            let localPlayerID = GKLocalPlayer.local.teamPlayerID

            for entry in globalEntries {
                entries.append(LeaderboardEntryData(
                    rank: max(1, entry.rank),
                    username: entry.player.displayName,
                    score: entry.score,
                    avatarEmoji: "",
                    level: 0,
                    isCurrentUser: entry.player.teamPlayerID == localPlayerID
                ))
            }

            var localPlayerData: LeaderboardEntryData?
            if let localEntry {
                localPlayerData = LeaderboardEntryData(
                    rank: max(1, localEntry.rank),
                    username: localEntry.player.displayName,
                    score: localEntry.score,
                    avatarEmoji: "",
                    level: 0,
                    isCurrentUser: true
                )
                // If local player isn't in the global list, add them
                if !entries.contains(where: { $0.isCurrentUser }) {
                    entries.append(localPlayerData!)
                    entries.sort { $0.rank < $1.rank }
                }
            }

            return LeaderboardResult(
                entries: entries,
                localPlayerEntry: localPlayerData,
                totalPlayerCount: totalCount
            )
        } catch {
            print("[GameCenterService] Failed to load leaderboard: \(error.localizedDescription)")
            return LeaderboardResult(entries: [], localPlayerEntry: nil, totalPlayerCount: 0, error: error)
        }
    }

    // MARK: - Score Reporting

    func reportScore(_ score: Int, leaderboardID: String) {
        guard isAuthenticated else { return }

        let ids = [leaderboardID]

        Task {
            do {
                print("[GameCenterService] Submitting score \(score) to \(ids)")
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: ids
                )
                print("[GameCenterService] Successfully submitted score \(score) to \(ids)")
            } catch {
                print("[GameCenterService] Failed to report score \(score) to \(ids): \(error.localizedDescription)")
            }
        }
    }

    func reportFocusLeagueScore(_ score: Int, for timeFilter: LeaderboardTimeFilter) {
        guard isAuthenticated else { return }

        Task {
            _ = await submitFocusLeagueScore(score, for: timeFilter)
        }
    }

    func submitFocusLeagueScore(_ score: Int, for timeFilter: LeaderboardTimeFilter) async -> Error? {
        guard isAuthenticated else { return nil }

        let leaderboardID = Self.focusLeaderboardID(for: timeFilter)
        do {
            print("[GameCenterService] Submitting Focus League score \(score) to \(leaderboardID)")
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            )
            print("[GameCenterService] Successfully submitted Focus League score \(score) to \(leaderboardID)")
            return nil
        } catch {
            print("[GameCenterService] Failed to report Focus League score: \(error.localizedDescription)")
            return error
        }
    }

    // MARK: - Achievement Reporting



    // MARK: - Show Game Center UI

    func showLeaderboard(leaderboardID: String) {
        guard isAuthenticated else { return }
        presentGameCenterVC(state: .leaderboards, leaderboardID: leaderboardID)
    }

    func showLeaderboard(category: LeaderboardCategory, timeFilter: LeaderboardTimeFilter) {
        guard isAuthenticated else { return }

        let leaderboardID = Self.leaderboardID(for: category, timeFilter: timeFilter)
        let timeScope = Self.gameCenterTimeScope(for: category, timeFilter: timeFilter)

        presentGameCenterVC(state: .leaderboards, leaderboardID: leaderboardID, timeScope: timeScope)
    }


    // MARK: - Private

    private func presentGameCenterVC(
        state: GKGameCenterViewControllerState,
        leaderboardID: String? = nil,
        timeScope: GKLeaderboard.TimeScope = .allTime
    ) {
        let gcVC: GKGameCenterViewController
        if let leaderboardID, state == .leaderboards {
            gcVC = GKGameCenterViewController(leaderboardID: leaderboardID, playerScope: .global, timeScope: timeScope)
        } else {
            gcVC = GKGameCenterViewController(state: state)
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }

        // Walk the presented VC chain to find the topmost one
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        gcVC.gameCenterDelegate = GameCenterDismissHandler.shared
        topVC.present(gcVC, animated: true)
    }
}

// MARK: - Dismiss Handler

/// Singleton handler for dismissing the Game Center view controller.
private final class GameCenterDismissHandler: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterDismissHandler()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
