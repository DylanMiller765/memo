import SwiftUI

enum UnlockFlowStage: Equatable {
    case slot
    case playing(UnlockGame)
    case freePass
    case escapeHatch
}

/// The whole unlock moment in one full-screen cover:
/// slot → game (arena) → cash-out choice → UNLOCKED / DENIED → escape hatch.
struct FocusUnlockFlowView: View {
    let onClose: () -> Void

    @Environment(FocusModeService.self) private var focusModeService
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: UnlockFlowStage = .slot
    @State private var run: UnlockRun?
    @State private var denials = 0
    @State private var qualifiedAt: Date?
    @State private var runStartedAt = Date()
    private let store = PendingSpinStore.shared

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()
            switch stage {
            case .slot:
                slot
            case .playing(let game):
                if let run {
                    arena(game: game, run: run)
                }
            case .freePass:
                UnlockedScreen(game: nil, outcome: .unlocked(minutes: UnlockRulebook.freePassMinutes, tier: .pass, score: 0, isPersonalBest: false)) {
                    grant(UnlockRulebook.freePassMinutes)
                }
            case .escapeHatch:
                EscapeHatchScreen(onComplete: {
                    Analytics.unlockEscapeHatch()
                    store.resolve()
                    grant(UnlockRulebook.escapeHatchMinutes)
                }, onCancel: onClose)
            }
        }
        .onChange(of: scenePhase) { _, phase in run?.setPaused(phase != .active) }
        .onChange(of: run?.phase) { _, phase in handle(phase) }
        .preferredColorScheme(.dark)
    }

    // MARK: Slot

    @ViewBuilder private var slot: some View {
        FocusUnlockSlotView(pending: store.current()?.game) { result in
            switch result {
            case .game(let game):
                store.begin(game)
                start(game)
            case .freePass:
                store.markFreePassUsed()
                Analytics.unlockFreePass()
                stage = .freePass
            }
        }
    }

    // MARK: Arena

    @ViewBuilder
    private func arena(game: UnlockGame, run: UnlockRun) -> some View {
        ZStack {
            UnlockGameHost(game: game, run: run)
                .id(ObjectIdentifier(run))
            if run.phase == .choosing {
                CashOutCard(run: run)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if case .ended(let outcome) = run.phase {
                endScreen(game: game, outcome: outcome)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: run.phase)
    }

    @ViewBuilder
    private func endScreen(game: UnlockGame, outcome: UnlockOutcome) -> some View {
        switch outcome {
        case .unlocked(let minutes, _, _, _):
            UnlockedScreen(game: game, outcome: outcome) {
                store.resolve()
                grant(minutes)
                // Asked on the way out ("Go scroll"), never over the ticket.
                ReviewPromptService.unlockEarned()
            }
        case .denied(let score, let distance):
            DeniedScreen(game: game, score: score, distance: distance, denials: denials,
                         onTryAgain: { start(game) },
                         onStayOff: {
                             NotificationCenter.default.post(name: .unlockResisted, object: nil)
                             UnlockStatsStore.shared.recordResisted()
                             store.resolve()
                             onClose()
                         },
                         onNeedIt: { stage = .escapeHatch })
        }
    }

    // MARK: Flow

    private func start(_ game: UnlockGame) {
        // Reaction Time is stored inverted (1000 − ms) so "higher is better" holds in the tracker.
        let stored = PersonalBestTracker.shared.best(for: game.exerciseType)
        let best = game.lowerIsBetter ? (stored > 0 ? 1000 - stored : 0) : stored
        run = UnlockRun(game: game, previousBest: best)
        qualifiedAt = nil
        runStartedAt = Date()
        stage = .playing(game)
        Analytics.unlockRunStarted(game: game.rawValue)
    }

    private func handle(_ phase: UnlockRun.Phase?) {
        guard let run, let phase else { return }
        switch phase {
        case .choosing:
            if qualifiedAt == nil {
                qualifiedAt = Date()
                Analytics.unlockQualified(game: run.game.rawValue, seconds: Int(Date().timeIntervalSince(runStartedAt)))
            }
        case .ended(.denied(let score, let distance)):
            denials = store.recordDenial()
            UnlockStatsStore.shared.recordDenied()
            Analytics.unlockRunEnded(game: run.game.rawValue, outcome: "denied", tier: 0, score: score, minutes: 0, isPB: false)
            Analytics.unlockDenied(game: run.game.rawValue, distance: distance)
        case .ended(.unlocked(let minutes, let tier, let score, let isPB)):
            UnlockStatsStore.shared.recordEarned(minutes: minutes)
            Analytics.unlockRunEnded(game: run.game.rawValue, outcome: "unlocked", tier: tier.rawValue, score: score, minutes: minutes, isPB: isPB)
        default:
            break
        }
    }

    private func grant(_ minutes: Int) {
        focusModeService.temporaryUnlock(durationMinutes: minutes)
        onClose()
    }
}

extension Notification.Name {
    static let unlockResisted = Notification.Name("unlockResisted")
}

/// Hosts the landed game in unlock mode.
struct UnlockGameHost: View {
    let game: UnlockGame
    let run: UnlockRun

    var body: some View {
        switch game {
        case .visualMemory: VisualMemoryView(autoStart: true, mode: .unlock(run))
        case .numberMemory: SequentialMemoryView(autoStart: true, mode: .unlock(run))
        case .chimpTest: ChimpTestView(autoStart: true, mode: .unlock(run))
        case .mathSprint: MathSpeedView(autoStart: true, mode: .unlock(run))
        case .colorMatch: ColorMatchView(autoStart: true, mode: .unlock(run))
        case .reactionTime: ReactionTimeView(autoStart: true, mode: .unlock(run))
        }
    }
}
