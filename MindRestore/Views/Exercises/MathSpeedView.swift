import SwiftUI
import SwiftData

// MARK: - ViewModel

/// Math Sprint: one draining time bank, auto-submitting keypad, problems that
/// get harder once you pass the qualify line. Score = questions completed.
@MainActor @Observable
final class MathSprintViewModel {
    private(set) var bank = TimeBank()
    private(set) var problem: SprintProblem
    private(set) var entry = ""
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
        problem = MathSprintEngine.problem(completed: 0, using: &seed)
    }

    var completed: Int { bank.completed }
    var isOvertime: Bool { completed >= MathSprintEngine.qualifyCount }
    var durationSeconds: Int { Int(Date().timeIntervalSince(startedAt)) }
    var accuracy: Double { Double(completed) / Double(max(1, completed + wrongCount)) }

    func start() {
        bank = TimeBank()
        wrongCount = 0
        entry = ""
        isOver = false
        startedAt = Date()
        lastTick = nil
        problem = MathSprintEngine.problem(completed: 0, using: &rng)
        started = true
    }

    func tick(now: Date, frozen: Bool) {
        defer { lastTick = frozen ? nil : now }
        guard started, !isOver, !frozen, let last = lastTick else { return }
        bank.elapse(now.timeIntervalSince(last))
        if bank.isEmpty { isOver = true }
    }

    func type(_ digit: Int) {
        guard started, !isOver, flash == .idle, entry.count < problem.digits else { return }
        entry.append(String(digit))
        guard entry.count == problem.digits else { return }
        if Int(entry) == problem.answer {
            let bonus = bank.correct()
            let text = bonus.truncatingRemainder(dividingBy: 1) == 0 ? "+\(Int(bonus))" : String(format: "+%.1f", bonus)
            float = FuseFloat(text: text, positive: true)
            flash = .correct
            HapticService.correct()
        } else {
            bank.wrong()
            wrongCount += 1
            float = FuseFloat(text: "−3", positive: false)
            flash = .wrong
            HapticService.wrong()
            if bank.isEmpty { isOver = true }
        }
        let next = MathSprintEngine.problem(completed: bank.completed, using: &rng)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.entry = ""
            self.flash = .idle
            self.problem = next
        }
    }

    func deleteDigit() {
        guard flash == .idle, !entry.isEmpty else { return }
        entry.removeLast()
    }
}

// MARK: - View

struct MathSpeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]

    var autoStart: Bool = false
    var mode: GameMode = .train

    @State private var viewModel = MathSprintViewModel()
    @State private var exerciseSaved = false
    @State private var isNewPersonalBest = false
    @State private var shakeAmount: CGFloat = 0

    private var user: User? { users.first }
    private var best: Int { PersonalBestTracker.shared.best(for: .mathSpeed) }

    var body: some View {
        GameScaffold(mode: mode, trainTitle: "Math Sprint", trainBest: best > 0 ? "\(best)" : nil,
                     glow: viewModel.isOvertime ? Color(red: 0.227, green: 0.102, blue: 0.071) : Color(red: 0.086, green: 0.094, blue: 0.227)) {
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
                Analytics.exerciseStarted(game: ExerciseType.mathSpeed.rawValue)
                viewModel.start()
            }
        }
        .onChange(of: viewModel.completed) { _, completed in
            mode.run?.report(score: completed)
        }
        .onChange(of: viewModel.isOver) { _, over in
            guard over else { return }
            isNewPersonalBest = PersonalBestTracker.shared.record(score: viewModel.completed, for: .mathSpeed)
            if isNewPersonalBest {
                Analytics.personalBest(game: ExerciseType.mathSpeed.rawValue, score: viewModel.completed)
            }
            saveExercise()
            mode.run?.finish(finalScore: viewModel.completed)
        }
        .onChange(of: viewModel.flash) { _, flash in
            if flash == .wrong { withAnimation(.default) { shakeAmount += 1 } }
        }
    }

    // MARK: Intro (Train mode, first run)

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("7 × 8")
                .font(HeroNumber.font(56))
                .foregroundStyle(LinearGradient.hero(Color(red: 0.56, green: 0.69, blue: 1)))
            Text("Math Sprint")
                .font(.brand(size: 28, weight: .black))
                .foregroundStyle(OB.fg)
            Text("Answer before the bar runs out.\nRight answers add time. Wrong ones cost 3 seconds.")
                .font(.brand(size: 15, weight: .semibold))
                .foregroundStyle(OB.fg2)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                Analytics.exerciseStarted(game: ExerciseType.mathSpeed.rawValue)
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

    // MARK: Playing

    private var playing: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            VStack(spacing: 0) {
                FuseBar(fraction: viewModel.bank.fraction, overtime: viewModel.isOvertime, floatText: viewModel.float)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                if viewModel.isOvertime {
                    Label("\(viewModel.completed)", systemImage: "flame.fill")
                        .font(.brand(size: 15, weight: .black))
                        .foregroundStyle(OB.amber)
                        .padding(.top, 14)
                        .contentTransition(.numericText())
                }
                Text(viewModel.problem.text)
                    .font(HeroNumber.font(56))
                    .foregroundStyle(OB.fg)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, viewModel.isOvertime ? 18 : 40)
                    .modifier(ShakeEffect(animatableData: shakeAmount))
                AnswerBoxes(entry: viewModel.entry, length: viewModel.problem.digits,
                            tint: viewModel.isOvertime ? OB.amber : OB.accent, flash: viewModel.flash)
                    .padding(.horizontal, 40)
                    .padding(.top, 14)
                Spacer(minLength: 12)
                BevelKeypad(onDigit: { viewModel.type($0) }, onDelete: { viewModel.deleteDigit() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .onChange(of: context.date) { _, now in
                viewModel.tick(now: now, frozen: mode.run?.isFrozen ?? false)
            }
        }
    }

    // MARK: Results (Train mode)

    private var results: some View {
        GameResultView(
            gameTitle: "Math Sprint",
            gameIcon: "multiply.circle.fill",
            accentColor: AppColors.amber,
            mainScore: viewModel.completed,
            scoreLabel: "QUESTIONS",
            ratingText: viewModel.completed >= 20 ? "Elite" : viewModel.completed >= 14 ? "Quick Thinker" : "Keep Practicing",
            stats: [
                (label: "Accuracy", value: "\(Int(viewModel.accuracy * 100))%"),
                (label: "Time", value: viewModel.durationSeconds.durationString)
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: best,
            exerciseType: .mathSpeed,
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
        paywallTrigger.recordExerciseCompleted(gameType: .mathSpeed)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        GameResultRecorder.record(
            type: .mathSpeed,
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
