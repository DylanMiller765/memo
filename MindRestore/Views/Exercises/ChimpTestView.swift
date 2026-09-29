import SwiftUI
import SwiftData
import ConfettiSwiftUI

// MARK: - ViewModel

@MainActor @Observable
final class ChimpTestViewModel {
    enum Phase: Equatable { case setup, playing, finished }

    var phase: Phase = .setup
    var startTime: Date?

    // Grid: 5 columns x 6 rows = 30 cells — fits every iPhone width.
    let columns = 5
    let rows = 6

    // Game state
    var currentLevel = 4
    var bestLevel = 0
    /// Called with the numbers count each time a level is completed.
    var onLevelCleared: ((Int) -> Void)?
    /// While true, the next level waits (cash-out choice, backgrounding).
    var holdAdvance = false {
        didSet { if !holdAdvance && pendingAdvance { pendingAdvance = false; setupLevel() } }
    }
    private var pendingAdvance = false
    /// Onboarding's demo: one life, so the run ends on the first miss.
    var isOnboardingPreview = false
    var lives = 3
    var nextExpected = 1
    var numbersHidden = false

    // Grid data: nil = empty, Int = number at that position
    var grid: [Int?] = Array(repeating: nil, count: 48)
    // Track which cells have been correctly tapped
    var correctCells: Set<Int> = []
    // Track wrong cell (briefly flash)
    var wrongCell: Int?

    var challengeSeed: Int?
    private var rng: SeededGenerator?

    // MARK: - Computed Properties

    var score: Double {
        // Normalize: level 4 = 0, level 20+ = 1.0
        let normalized = Double(bestLevel - 4) / 16.0
        return min(1.0, max(0.0, normalized))
    }

    var durationSeconds: Int {
        guard let start = startTime else { return 0 }
        return Int(Date.now.timeIntervalSince(start))
    }

    var leaderboardScore: Int {
        bestLevel
    }

    var difficulty: Int {
        if bestLevel >= 14 { return 10 }
        if bestLevel >= 12 { return 8 }
        if bestLevel >= 10 { return 6 }
        if bestLevel >= 8 { return 5 }
        if bestLevel >= 6 { return 3 }
        return 1
    }

    var ratingText: String {
        if bestLevel >= 12 { return "Genius!" }
        if bestLevel >= 10 { return "Amazing!" }
        if bestLevel >= 8 { return "Great!" }
        if bestLevel >= 6 { return "Good Job!" }
        return "Keep Practicing!"
    }

    var totalNumbers: Int { currentLevel }

    // MARK: - Game Logic

    func startGame() {
        GameSound.resetCombo()
        phase = .playing
        currentLevel = 4
        bestLevel = 0
        lives = isOnboardingPreview ? 1 : 3
        startTime = Date.now
        if let seed = challengeSeed {
            rng = SeededGenerator(seed: UInt64(seed))
        } else {
            rng = nil
        }
        setupLevel()
    }

    func setupLevel() {
        nextExpected = 1
        numbersHidden = false
        correctCells = []
        wrongCell = nil
        grid = Array(repeating: nil, count: columns * rows)

        // Place numbers 1..currentLevel at random positions
        var positions = Array(0..<(columns * rows))
        if var r = rng {
            positions.shuffle(using: &r)
            rng = r
        } else {
            positions.shuffle()
        }

        for number in 1...currentLevel {
            let pos = positions[number - 1]
            grid[pos] = number
        }
    }

    func tapCell(at index: Int) {
        guard phase == .playing else { return }
        guard let number = grid[index] else { return }
        guard !correctCells.contains(index) else { return }

        if number == nextExpected {
            // Correct tap
            correctCells.insert(index)
            HapticService.tap()

            if nextExpected == 1 {
                // After tapping 1, hide all remaining numbers
                numbersHidden = true
            }

            nextExpected += 1

            // Check if level complete
            if nextExpected > currentLevel {
                // Level complete!
                HapticService.correct()
                GameSound.levelUp()
                bestLevel = max(bestLevel, currentLevel)
                currentLevel += 1
                onLevelCleared?(bestLevel)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    if self.holdAdvance { self.pendingAdvance = true } else { self.setupLevel() }
                }
            }
        } else {
            // Wrong tap
            wrongCell = index
            HapticService.wrong()
            GameSound.wrong()
            lives -= 1

            if lives <= 0 {
                // Game over
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.finishGame()
                }
            } else {
                // Lose a life, restart current level
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.setupLevel()
                }
            }
        }
    }

    private func finishGame() {
        // bestLevel now tracks the highest level actually completed (set before currentLevel increments)
        phase = .finished
        GameSound.complete()
        HapticService.complete()
    }

    func reset() {
        phase = .setup
        currentLevel = 4
        bestLevel = 0
        lives = 3
        startTime = nil
        numbersHidden = false
        nextExpected = 1
        correctCells = []
        wrongCell = nil
        grid = Array(repeating: nil, count: columns * rows)
    }
}

// MARK: - View

struct ChimpTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query private var users: [User]

    /// Skip the setup screen on appear when entering from a Focus unlock.
    var autoStart: Bool = false

    var mode: GameMode = .train
    /// Onboarding's demo: no chrome, nothing saved, ends on the first miss.
    var isOnboardingPreview = false
    var onPreviewComplete: (() -> Void)? = nil
    /// Numbers remembered so far (the level just cleared).
    var onPreviewProgress: ((Int) -> Void)? = nil
    @State private var viewModel = ChimpTestViewModel()
    @State private var showingPaywall = false
    @State private var isNewPersonalBest = false
    @State private var exerciseSaved = false
    @State private var resultsAppeared = false
    @State private var showingInfo = false
    @State private var confettiCounter = 0

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser || (user?.isProUser ?? false) }

    var body: some View {
        if isOnboardingPreview {
            phaseContent
        } else {
            GameScaffold(mode: mode, trainTitle: "Chimp Test",
                         trainBest: PersonalBestTracker.shared.best(for: .chimpTest) > 0 ? "\(PersonalBestTracker.shared.best(for: .chimpTest))" : nil,
                         glow: Color(red: 0.2, green: 0.145, blue: 0.047)) {
                phaseContent
            }
        }
    }

    private var phaseContent: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .setup:
                setupView
                    .transition(.opacity)
            case .playing:
                playingView
                    .transition(.opacity)
            case .finished:
                if mode.run != nil || isOnboardingPreview {
                    Color.clear
                } else {
                    resultsView
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .sheet(isPresented: $showingPaywall) { PaywallView(isHighIntent: true) }
        .navigationTitle("Chimp Test")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.phase == .playing)
        .onAppear {
            if let run = mode.run {
                viewModel.onLevelCleared = { run.report(score: $0) }
            }
            if autoStart && viewModel.phase == .setup {
                viewModel.isOnboardingPreview = isOnboardingPreview
                if !isOnboardingPreview {
                    Analytics.exerciseStarted(game: ExerciseType.chimpTest.rawValue)
                }
                viewModel.startGame()
            }
        }
        .onDisappear {
            if isOnboardingPreview {
                viewModel.reset()
            } else if viewModel.phase == .playing {
                Analytics.exerciseAbandoned(game: ExerciseType.chimpTest.rawValue, roundReached: viewModel.currentLevel)
            }
        }
        .onChange(of: mode.run?.isFrozen ?? false) { _, frozen in
            viewModel.holdAdvance = frozen
        }
        .onChange(of: viewModel.bestLevel) { _, newValue in
            if isOnboardingPreview && newValue > 0 { onPreviewProgress?(newValue) }
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .finished {
                if isOnboardingPreview {
                    onPreviewComplete?()
                    return
                }
                isNewPersonalBest = PersonalBestTracker.shared.record(score: viewModel.leaderboardScore, for: .chimpTest)
                if isNewPersonalBest {
                    Analytics.personalBest(game: ExerciseType.chimpTest.rawValue, score: viewModel.leaderboardScore)
                }
                AdaptiveDifficultyEngine.shared.recordBlock(domain: .chimpTest, correct: max(0, viewModel.bestLevel - 4), total: max(1, viewModel.bestLevel))
                saveExercise()
                mode.run?.finish(finalScore: viewModel.bestLevel)
            }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        GameIntro(
            game: .chimpTest,
            subtitle: "Can you beat a chimp?",
            steps: [
                (icon: "1.circle.fill", text: "Tap 1 first. The rest hide."),
                (icon: "list.number", text: "Tap the rest in order"),
                (icon: "heart.fill", text: "3 lives. Each level adds a number."),
            ],
            onStart: {
                Analytics.exerciseStarted(game: ExerciseType.chimpTest.rawValue)
                viewModel.startGame()
            }
        )
        .overlay(alignment: .topTrailing) {
            Button { showingInfo = true } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
        }
        .sheet(isPresented: $showingInfo) {
            ExerciseInfoSheet(type: .chimpTest)
                .presentationDetents([.medium])
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.amber)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Playing

    private var playingView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let cols = viewModel.columns
            let tile = floor((min(geo.size.width - 32, 400) - 16 - spacing * CGFloat(cols - 1)) / CGFloat(cols))
            VStack(spacing: 0) {
                Text("\(viewModel.currentLevel)")
                    .font(HeroNumber.font(64))
                    .foregroundStyle(LinearGradient.hero(Color(red: 1, green: 0.85, blue: 0.54)))
                    .contentTransition(.numericText())
                    .padding(.top, 14)
                Group {
                    if viewModel.numbersHidden || viewModel.lives < 3 {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: i < viewModel.lives ? "heart.fill" : "heart")
                                    .foregroundStyle(i < viewModel.lives ? OB.coral : OB.fg3)
                            }
                        }
                        .accessibilityLabel("\(viewModel.lives) lives")
                    } else {
                        Label("chimps average 7. can you?", systemImage: "pawprint.fill")
                    }
                }
                .font(.brand(size: 13, weight: .bold))
                .foregroundStyle(OB.fg2)
                .padding(.top, 6)
                Spacer(minLength: 12)
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    ForEach(0..<viewModel.rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<cols, id: \.self) { col in
                                cellView(at: row * cols + col, size: tile)
                            }
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.063, green: 0.067, blue: 0.133))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
                )
                Spacer(minLength: 12)
                Text(viewModel.numbersHidden ? "from memory…" : "tap 1 — then they vanish")
                    .font(.brand(size: 13, weight: .heavy))
                    .foregroundStyle(OB.fg3)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func cellView(at index: Int, size: CGFloat) -> some View {
        let number = viewModel.grid.indices.contains(index) ? viewModel.grid[index] : nil
        let isCorrect = viewModel.correctCells.contains(index)
        let isWrong = viewModel.wrongCell == index
        return Group {
            if let number {
                let state: BevelState = isWrong ? .wrong : isCorrect ? .correct : .lit
                BevelTile(state: state, tint: OB.amber, cornerRadius: 10) {
                    Text(isCorrect ? "✓" : (viewModel.numbersHidden ? "" : "\(number)"))
                        .font(HeroNumber.font(size * 0.45))
                        .foregroundStyle(isCorrect ? Color(red: 0, green: 0.23, blue: 0.17) : Color(red: 0.23, green: 0.14, blue: 0))
                }
                .onTapGesture { viewModel.tapCell(at: index) }
                .accessibilityLabel(viewModel.numbersHidden ? "Hidden tile" : "Number \(number)")
            } else {
                BevelTile(state: .idle, cornerRadius: 10)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Results

    private var resultsView: some View {
        return GameResultView(
            gameTitle: "Chimp Test",
            gameIcon: "pawprint.fill",
            accentColor: AppColors.amber,
            mainScore: viewModel.bestLevel,
            scoreLabel: "NUMBERS REMEMBERED",
            ratingText: viewModel.ratingText,
            stats: [
                (label: "Best Level", value: "\(viewModel.bestLevel)"),
                (label: "Time", value: viewModel.durationSeconds.durationString)
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: PersonalBestTracker.shared.best(for: .chimpTest),
            exerciseType: .chimpTest,
            leaderboardScore: viewModel.bestLevel,
            emoji: "🐵",
            subtitleText: viewModel.bestLevel > 7 ? "You beat the chimp!" : viewModel.bestLevel == 7 ? "Tied with the chimp!" : "The chimp wins this time!",
            onPlayAgain: {
                exerciseSaved = false
                viewModel.reset()
            },
            onDone: { dismiss() }
        )
    }

    // MARK: - Save

    private func saveExercise() {
        guard !exerciseSaved else { return }
        exerciseSaved = true
        paywallTrigger.recordExerciseCompleted(gameType: .chimpTest)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        GameResultRecorder.record(
            type: .chimpTest,
            accuracy: viewModel.score,
            difficulty: viewModel.difficulty,
            durationSeconds: viewModel.durationSeconds,
            leaderboardScore: viewModel.bestLevel,
            user: user,
            modelContext: modelContext,
            gameCenter: gameCenterService
        )
    }
}
