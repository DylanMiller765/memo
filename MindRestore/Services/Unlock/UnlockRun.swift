import Foundation
import Observation

enum UnlockOutcome: Equatable {
    case unlocked(minutes: Int, tier: UnlockTier, score: Int, isPersonalBest: Bool)
    case denied(score: Int, distance: Int)
}

@MainActor
@Observable
final class UnlockRun {
    enum Phase: Equatable { case playing, choosing, overtime, ended(UnlockOutcome) }

    let game: UnlockGame
    let previousBest: Int
    private(set) var phase: Phase = .playing
    private(set) var score: Int = 0
    private(set) var roundsPlayed: Int = 0
    private(set) var isPaused = false
    private var hasChosen = false

    init(game: UnlockGame, previousBest: Int) {
        self.game = game
        self.previousBest = previousBest
    }

    var isEnded: Bool { if case .ended = phase { return true } else { return false } }
    var isFrozen: Bool { isPaused || phase == .choosing || isEnded }
    var bankedTier: UnlockTier { UnlockRulebook.tier(for: game, score: score) }
    var progress: BannerProgress { UnlockRulebook.bannerProgress(game: game, score: score, roundsPlayed: roundsPlayed) }
    var isPersonalBest: Bool { UnlockRulebook.isPersonalBest(game: game, score: score, previousBest: previousBest) }
    var liveMinutes: Int { UnlockRulebook.minutes(for: bankedTier, isPersonalBest: isPersonalBest) }

    func report(score newScore: Int) {
        guard !isEnded else { return }
        score = newScore
        if game.isEndless, !hasChosen, phase == .playing, bankedTier >= .pass {
            hasChosen = true
            phase = .choosing
        }
    }

    func reportRound(averageMs: Int, roundsPlayed rounds: Int) {
        guard !isEnded else { return }
        score = averageMs
        roundsPlayed = rounds
    }

    func cashOut() {
        guard phase == .choosing else { return }
        end()
    }

    func keepGoing() {
        guard phase == .choosing else { return }
        phase = .overtime
    }

    func finish(finalScore: Int) {
        guard !isEnded else { return }
        score = finalScore
        end()
    }

    func abandon() {
        guard !isEnded else { return }
        end()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    private func end() {
        let tier = bankedTier
        if tier == .none {
            phase = .ended(.denied(score: score, distance: UnlockRulebook.distanceToPass(game: game, score: score)))
        } else {
            phase = .ended(.unlocked(minutes: UnlockRulebook.minutes(for: tier, isPersonalBest: isPersonalBest),
                                     tier: tier, score: score, isPersonalBest: isPersonalBest))
        }
    }
}
