import SwiftUI
import SwiftData

// MARK: - ViewModel

/// Color Match: Stroop prompts on one draining time bank. Right answers add
/// time, wrong ones cost 3 seconds; a fifth color joins past the qualify line.
/// Score = prompts answered correctly.
@MainActor @Observable
final class ColorMatchSprintViewModel {
    private(set) var bank = TimeBank()
    private(set) var prompt: StroopPrompt
    private(set) var flash: BevelState = .idle
    private(set) var float: FuseFloat?
    private(set) var isOver = false
    private(set) var wrongCount = 0
    private(set) var started = false
    private var rng = SystemRandomNumberGenerator()
    private var lastTick: Date?
    private(set) var startedAt = Date()

    init() {
        var seed = SystemRandomNumberGenerator()
        prompt = ColorMatchEngine.prompt(completed: 0, previous: nil, using: &seed)
    }

    var completed: Int { bank.completed }
    var isOvertime: Bool { completed >= ColorMatchEngine.qualifyCount }
    var durationSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }
    var accuracy: Double { Double(completed) / Double(max(1, completed + wrongCount)) }

    func start() {
        GameSound.resetCombo()
        bank = TimeBank()
        wrongCount = 0
        flash = .idle
        isOver = false
        startedAt = Date()
        lastTick = nil
        prompt = ColorMatchEngine.prompt(completed: bank.completed, previous: nil, using: &rng)
        started = true
    }

    func tick(now: Date, frozen: Bool) {
        defer { lastTick = frozen ? nil : now }
        guard started, !isOver, !frozen, let last = lastTick else { return }
        bank.elapse(now.timeIntervalSince(last))
        if bank.isEmpty { isOver = true }
    }

    func choose(_ color: InkColor) {
        guard started, !isOver, flash == .idle else { return }
        if color == prompt.ink {
            let bonus = bank.correct()
            let text = bonus.truncatingRemainder(dividingBy: 1) == 0 ? "+\(Int(bonus))" : String(format: "+%.1f", bonus)
            float = FuseFloat(text: text, positive: true)
            flash = .correct
            HapticService.correct()
            GameSound.levelUp()
        } else {
            bank.wrong()
            wrongCount += 1
            float = FuseFloat(text: "−3", positive: false)
            flash = .wrong
            HapticService.wrong()
            GameSound.wrong()
            if bank.isEmpty { isOver = true }
        }
        let next = ColorMatchEngine.prompt(completed: bank.completed, previous: prompt, using: &rng)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.flash = .idle
            self.prompt = next
        }
    }
}

// MARK: - View

struct ColorMatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]

    var autoStart: Bool = false
    var mode: GameMode = .train

    @State private var viewModel = ColorMatchSprintViewModel()
    @State private var exerciseSaved = false
    @State private var isNewPersonalBest = false
    @State private var shakeAmount: CGFloat = 0
    @State private var correctPop = false

    private var user: User? { users.first }
    private var best: Int { PersonalBestTracker.shared.best(for: .colorMatch) }

    var body: some View {
        GameScaffold(mode: mode, trainTitle: "Color Match", trainBest: best > 0 ? "\(best)" : nil,
                     glow: viewModel.isOvertime ? Color(red: 0.227, green: 0.102, blue: 0.071) : Color(red: 0.13, green: 0.07, blue: 0.2)) {
            Group {
                if !viewModel.started {
                    intro
                } else if viewModel.isOver {
                    if mode.run != nil { Color.clear } else { results }
                } else {
                    playing
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewModel.isOvertime)
        }
        .onAppear {
            if autoStart && !viewModel.started {
                Analytics.exerciseStarted(game: ExerciseType.colorMatch.rawValue)
                viewModel.start()
            }
        }
        .onChange(of: viewModel.completed) { _, completed in
            mode.run?.report(score: completed)
        }
        .onChange(of: viewModel.isOver) { _, over in
            guard over else { return }
            isNewPersonalBest = PersonalBestTracker.shared.record(score: viewModel.completed, for: .colorMatch)
            if isNewPersonalBest {
                Analytics.personalBest(game: ExerciseType.colorMatch.rawValue, score: viewModel.completed)
            }
            saveExercise()
            mode.run?.finish(finalScore: viewModel.completed)
        }
        .onChange(of: viewModel.flash) { _, flash in
            switch flash {
            case .wrong:
                withAnimation(.default) { shakeAmount += 1 }
            case .correct:
                withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) { correctPop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeOut(duration: 0.12)) { correctPop = false }
                }
            default:
                break
            }
        }
    }

    // MARK: Intro (Train mode, first run)

    private var intro: some View {
        GameIntro(
            game: .colorMatch,
            subtitle: "Tap the ink, not the word.",
            steps: [
                (icon: "paintpalette.fill", text: "Tap the ink color, not the word"),
                (icon: "plus", text: "Right answers add time"),
                (icon: "minus", text: "Wrong answers cost 3 seconds"),
            ],
            onStart: {
                Analytics.exerciseStarted(game: ExerciseType.colorMatch.rawValue)
                viewModel.start()
            }
        )
    }

    // MARK: Playing

    private var playing: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            VStack(spacing: 0) {
                FuseBar(fraction: viewModel.bank.fraction, overtime: viewModel.isOvertime, floatText: viewModel.float)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                Text(viewModel.prompt.word.label)
                    .font(HeroNumber.font(64))
                    .foregroundStyle(viewModel.prompt.ink.color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 70)
                    .scaleEffect(correctPop ? 1.08 : 1)
                    .modifier(ShakeEffect(animatableData: shakeAmount))
                    .accessibilityLabel("The word \(viewModel.prompt.word.label) in \(viewModel.prompt.ink.label) ink")
                Text("tap the COLOR, not the word")
                    .font(.brand(size: 13, weight: .heavy))
                    .foregroundStyle(OB.fg2)
                    .padding(.top, 10)
                Spacer(minLength: 12)
                swatches
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .onChange(of: context.date) { _, now in
                viewModel.tick(now: now, frozen: mode.run?.isFrozen ?? false)
            }
        }
    }

    /// Two columns; an odd last color (purple, in overtime) sits alone, centered.
    private var swatches: some View {
        let choices = viewModel.prompt.choices
        let rows = stride(from: 0, to: choices.count, by: 2).map { Array(choices[$0..<min($0 + 2, choices.count)]) }
        return GeometryReader { geo in
            let width = (geo.size.width - 10) / 2
            VStack(spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { color in
                            swatch(color).frame(width: width)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: CGFloat(rows.count) * 64 + CGFloat(rows.count - 1) * 10)
        .animation(.easeInOut(duration: 0.25), value: choices.count)
    }

    private func swatch(_ color: InkColor) -> some View {
        Button {
            viewModel.choose(color)
        } label: {
            BevelTile(state: .lit, tint: color.color, cornerRadius: 16) {
                Text(color.label)
                    .font(.brand(size: 18, weight: .black))
                    .foregroundStyle(color == .yellow ? .black : .white)
                    .shadow(radius: 2)
            }
            .frame(height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Answer \(color.label.lowercased())")
    }

    // MARK: Results (Train mode)

    private var results: some View {
        GameResultView(
            gameTitle: "Color Match",
            gameIcon: "paintpalette.fill",
            accentColor: AppColors.violet,
            mainScore: viewModel.completed,
            scoreLabel: "CORRECT",
            ratingText: viewModel.completed >= 26 ? "Stroop Master" : viewModel.completed >= 18 ? "Sharp Focus" : "Keep Practicing",
            stats: [
                (label: "Accuracy", value: "\(Int(viewModel.accuracy * 100))%"),
                (label: "Time", value: viewModel.durationSeconds.durationString)
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: best,
            exerciseType: .colorMatch,
            leaderboardScore: viewModel.completed,
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
        paywallTrigger.recordExerciseCompleted(gameType: .colorMatch)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        GameResultRecorder.record(
            type: .colorMatch,
            accuracy: viewModel.accuracy,
            difficulty: viewModel.completed,
            durationSeconds: viewModel.durationSeconds,
            leaderboardScore: viewModel.completed,
            user: user,
            modelContext: modelContext,
            gameCenter: gameCenterService
        )
    }
}
