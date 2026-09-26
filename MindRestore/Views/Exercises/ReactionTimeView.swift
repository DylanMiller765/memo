import SwiftUI
import SwiftData

// MARK: - ViewModel

enum RTPhase: Equatable {
    case setup
    case waiting
    case ready
    case tooSoon
    case result
    case finished
}

/// Reaction Time: 5 valid rounds, score = average ms (lower is better).
/// A false start shows "TOO SOON!" and replays the same round.
@MainActor @Observable
final class ReactionTimeViewModel {
    static let rounds = 5

    private(set) var phase: RTPhase = .setup
    private(set) var reactionTimes: [Int] = []
    private(set) var lastReactionMs = 0
    private(set) var startTime: Date?
    private var goAt: Date?
    /// Bumped whenever a scheduled step becomes stale (tap, freeze, restart).
    private var generation = 0
    private var isFrozen = false

    var validRounds: Int { reactionTimes.count }

    var averageMs: Int {
        guard !reactionTimes.isEmpty else { return 0 }
        return reactionTimes.reduce(0, +) / reactionTimes.count
    }

    var bestMs: Int { reactionTimes.min() ?? 0 }

    /// 200 ms or less = 1.0, 500 ms+ = 0.0.
    var accuracy: Double {
        let avg = Double(averageMs)
        guard avg > 0 else { return 0 }
        return max(0, min(1, (500 - avg) / 300))
    }

    var durationSeconds: Int {
        guard let startTime else { return 0 }
        return Int(Date.now.timeIntervalSince(startTime))
    }

    static func verdict(for ms: Int) -> String {
        if ms < 250 { return "LIGHTNING ⚡" }
        if ms < 320 { return "QUICK" }
        if ms < 400 { return "SOLID" }
        return "SLOW"
    }

    func start() {
        reactionTimes = []
        lastReactionMs = 0
        startTime = .now
        startRound()
    }

    func tap() {
        switch phase {
        case .waiting:
            generation += 1
            HapticService.wrong()
            phase = .tooSoon
            schedule(after: 0.8) { $0.startRound() }
        case .ready:
            guard let goAt else { return }
            generation += 1
            let ms = Int(Date.now.timeIntervalSince(goAt) * 1000)
            lastReactionMs = ms
            reactionTimes.append(ms)
            HapticService.tap()
            phase = .result
            schedule(after: 1.2) { $0.nextOrFinish() }
        default:
            break
        }
    }

    /// Backgrounding cancels the pending "go green" and replays the round from "wait…" on return.
    func setFrozen(_ frozen: Bool) {
        guard frozen != isFrozen else { return }
        isFrozen = frozen
        generation += 1
        guard !frozen else { return }
        switch phase {
        case .waiting, .ready, .tooSoon: startRound()
        case .result: nextOrFinish()
        default: break
        }
    }

    private func startRound() {
        goAt = nil
        phase = .waiting
        schedule(after: Double.random(in: 1.5...4.0)) { vm in
            vm.goAt = .now
            vm.phase = .ready
        }
    }

    private func nextOrFinish() {
        if validRounds >= Self.rounds {
            HapticService.complete()
            phase = .finished
        } else {
            startRound()
        }
    }

    private func schedule(after delay: Double, _ step: @escaping (ReactionTimeViewModel) -> Void) {
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token, !self.isFrozen else { return }
            step(self)
        }
    }
}

// MARK: - View

struct ReactionTimeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]

    var autoStart: Bool = false
    var mode: GameMode = .train

    @State private var viewModel = ReactionTimeViewModel()
    @State private var exerciseSaved = false
    @State private var isNewPersonalBest = false

    private var user: User? { users.first }
    /// PersonalBestTracker stores Reaction Time inverted (1000 − ms) so higher is better.
    private var bestMs: Int {
        let inverted = PersonalBestTracker.shared.best(for: .reactionTime)
        return inverted > 0 ? 1000 - inverted : 0
    }

    private var isGreen: Bool { viewModel.phase == .ready || viewModel.phase == .result }
    private var isArena: Bool { ![.setup, .finished].contains(viewModel.phase) }

    var body: some View {
        GameScaffold(mode: mode, trainTitle: "Reaction Time", trainBest: bestMs > 0 ? "\(bestMs)ms" : nil,
                     glow: .clear, backdrop: isArena ? AnyView(arenaBackground) : nil) {
            Group {
                switch viewModel.phase {
                case .setup:
                    intro
                case .finished:
                    if mode.run != nil { Color.clear } else { results }
                default:
                    arena
                }
            }
        }
        .onAppear {
            if autoStart && viewModel.phase == .setup {
                Analytics.exerciseStarted(game: ExerciseType.reactionTime.rawValue)
                viewModel.start()
            }
        }
        .onChange(of: mode.run?.isFrozen ?? false) { _, frozen in
            viewModel.setFrozen(frozen)
        }
        .onChange(of: viewModel.validRounds) { _, rounds in
            guard rounds > 0 else { return }
            mode.run?.reportRound(averageMs: viewModel.averageMs, roundsPlayed: rounds)
        }
        .onChange(of: viewModel.phase) { _, phase in
            guard phase == .finished else { return }
            let average = viewModel.averageMs
            isNewPersonalBest = PersonalBestTracker.shared.record(score: 1000 - average, for: .reactionTime)
            if isNewPersonalBest {
                Analytics.personalBest(game: ExerciseType.reactionTime.rawValue, score: average)
            }
            saveExercise()
            mode.run?.finish(finalScore: average)
        }
    }

    // MARK: Intro (Train mode, first run)

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("⚡")
                .font(.system(size: 56))
            Text("Reaction Time")
                .font(.brand(size: 28, weight: .black))
                .foregroundStyle(OB.fg)
            Text("Tap the moment the screen turns green.\n5 rounds. Tap early and the round replays.")
                .font(.brand(size: 15, weight: .semibold))
                .foregroundStyle(OB.fg2)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                Analytics.exerciseStarted(game: ExerciseType.reactionTime.rawValue)
                viewModel.start()
            } label: {
                Text("Start")
                    .font(.brand(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OB.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Arena

    private var arenaBackground: some View {
        let colors = isGreen
            ? [Color(red: 0.36, green: 1.0, blue: 0.61), Color(red: 0.09, green: 0.76, blue: 0.40), Color(red: 0.04, green: 0.54, blue: 0.28)]
            : [Color(red: 1, green: 0.35, blue: 0.29), Color(red: 0.70, green: 0.15, blue: 0.12), Color(red: 0.48, green: 0.09, blue: 0.07)]
        return RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 560)
    }

    private var arena: some View {
        VStack(spacing: 0) {
            Spacer()
            center
            Spacer()
            Text(footer)
                .font(.brand(size: 15, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 28)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.tap() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(viewModel.phase == .ready ? "Tap now" : "Wait for green")
    }

    @ViewBuilder private var center: some View {
        switch viewModel.phase {
        case .tooSoon:
            Text("TOO SOON!")
                .font(HeroNumber.font(48))
                .foregroundStyle(.white)
        case .result:
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(viewModel.lastReactionMs)")
                        .font(HeroNumber.font(72))
                    Text("ms")
                        .font(HeroNumber.font(28))
                }
                .foregroundStyle(.white)
                Text(ReactionTimeViewModel.verdict(for: viewModel.lastReactionMs))
                    .font(.system(size: 26, weight: .heavy).italic())
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-4))
                roundDots.padding(.top, 14)
            }
            .accessibilityElement(children: .combine)
        default:
            VStack(spacing: 22) {
                Text(viewModel.phase == .ready ? "TAP!" : "wait…")
                    .font(HeroNumber.font(64))
                    .foregroundStyle(.white)
                roundDots
            }
        }
    }

    private var roundDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<ReactionTimeViewModel.rounds, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i < viewModel.validRounds ? 1 : 0.35))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityHidden(true)
    }

    private var footer: String {
        switch viewModel.phase {
        case .result: "avg so far \(viewModel.averageMs)ms"
        case .tooSoon: " "
        default: "tap when it turns green"
        }
    }

    // MARK: Results (Train mode)

    private var results: some View {
        GameResultView(
            gameTitle: "Reaction Time",
            gameIcon: "bolt.fill",
            accentColor: AppColors.coral,
            mainScore: viewModel.averageMs,
            scoreLabel: "MILLISECONDS",
            ratingText: ReactionTimeViewModel.verdict(for: viewModel.averageMs).capitalized,
            stats: [
                (label: "Average", value: "\(viewModel.averageMs) ms"),
                (label: "Best", value: "\(viewModel.bestMs) ms")
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: bestMs,
            exerciseType: .reactionTime,
            leaderboardScore: viewModel.averageMs,
            onPlayAgain: {
                exerciseSaved = false
                viewModel.start()
            },
            onDone: { dismiss() }
        )
    }

    // MARK: Save

    private func saveExercise() {
        guard !exerciseSaved else { return }
        exerciseSaved = true
        paywallTrigger.recordExerciseCompleted(gameType: .reactionTime)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        GameResultRecorder.record(
            type: .reactionTime,
            accuracy: viewModel.accuracy,
            difficulty: 1,
            durationSeconds: viewModel.durationSeconds,
            leaderboardScore: viewModel.averageMs,
            user: user,
            modelContext: modelContext,
            gameCenter: gameCenterService
        )
    }
}
