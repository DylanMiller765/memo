import SwiftUI
import SwiftData
import GameKit

// MARK: - Game Phase

enum SMPhase {
    case setup
    case showing
    case input
    case roundResult
    case finished
}

// MARK: - ViewModel

@MainActor @Observable
final class SequentialMemoryViewModel {
    var phase: SMPhase = .setup
    var currentDigits: [Int] = []
    var displayDigitIndex: Int = -1
    var userInput: String = ""
    var startLength: Int = 4
    var currentLength: Int = 4
    let adaptiveLevel = AdaptiveDifficultyEngine.shared.currentLevel(for: .sequentialMemory)
    var round: Int = 0
    var maxRounds: Int = 8
    var maxCorrectLength: Int = 0
    var roundResults: [(length: Int, correct: Bool)] = []
    var startTime: Date?
    var challengeSeed: Int?
    private var rng: SeededGenerator?
    private var digitTimer: Timer?
    /// Called with the digit count each time a number is recalled correctly.
    var onLevelCleared: ((Int) -> Void)?
    /// While true, the next number waits (cash-out choice, backgrounding).
    var holdAdvance = false {
        didSet { if !holdAdvance { tryAdvance() } }
    }
    private var pendingAdvance = false
    /// Seconds the whole number stays on screen: 1.0 + 0.6 per digit.
    var displayDuration: TimeInterval { 1.0 + 0.6 * Double(currentLength) }
    var lastAnswerCorrect = false
    var targetNumber: String { currentDigits.map(String.init).joined() }

    var score: Double {
        // maxCorrectLength of 4 = baseline (0.5), 10+ = perfect
        let normalized = Double(maxCorrectLength - 3) / 7.0
        return max(0, min(1, normalized))
    }

    var durationSeconds: Int {
        guard let start = startTime else { return 0 }
        return Int(Date.now.timeIntervalSince(start))
    }

    var currentDisplayDigit: String {
        guard displayDigitIndex >= 0, displayDigitIndex < currentDigits.count else { return "" }
        return "\(currentDigits[displayDigitIndex])"
    }

    var isShowingDigit: Bool {
        displayDigitIndex >= 0 && displayDigitIndex < currentDigits.count
    }

    func startGame() {
        GameSound.resetCombo()
        currentLength = 3
        round = 0
        maxCorrectLength = 0
        roundResults = []
        startTime = Date.now
        if let seed = challengeSeed {
            rng = SeededGenerator(seed: UInt64(seed))
        } else {
            rng = nil
        }
        nextRound()
    }

    func nextRound() {
        if var r = rng {
            currentDigits = (0..<currentLength).map { _ in Int.random(in: 0...9, using: &r) }
            rng = r
        } else {
            currentDigits = (0..<currentLength).map { _ in Int.random(in: 0...9) }
        }
        userInput = ""
        phase = .showing
        digitTimer?.invalidate()
        digitTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.phase = .input }
        }
    }



    func type(_ digit: Int) {
        guard phase == .input, userInput.count < currentLength else { return }
        userInput.append(String(digit))
        if userInput.count == currentLength { submitAnswer() }
    }

    func deleteDigit() {
        guard phase == .input, !userInput.isEmpty else { return }
        userInput.removeLast()
    }

    func submitAnswer() {
        let isCorrect = userInput == targetNumber
        lastAnswerCorrect = isCorrect
        roundResults.append((length: currentLength, correct: isCorrect))
        round += 1
        phase = .roundResult
        digitTimer?.invalidate()
        if isCorrect {
            maxCorrectLength = max(maxCorrectLength, currentLength)
            HapticService.correct()
            GameSound.levelUp()
            onLevelCleared?(maxCorrectLength)
            digitTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.pendingAdvance = true
                    self?.tryAdvance()
                }
            }
        } else {
            HapticService.wrong()
            digitTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.phase = .finished }
            }
        }
    }

    func tryAdvance() {
        guard pendingAdvance, !holdAdvance, phase == .roundResult else { return }
        pendingAdvance = false
        currentLength += 1
        nextRound()
    }



    var correctRounds: Int {
        roundResults.filter(\.correct).count
    }

    func reset() {
        digitTimer?.invalidate()
        phase = .setup
    }
}

// MARK: - View

struct SequentialMemoryView: View {
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
    @State private var viewModel = SequentialMemoryViewModel()
    @State private var showingPaywall = false
    @State private var isNewPersonalBest = false
    @State private var shareImage: UIImage?
    @State private var exerciseSaved = false
    @State private var shakeAmount: CGFloat = 0
    @State private var correctPulse = false
    @State private var showingInfo = false
    @State private var showStartedAt = Date()
    @FocusState private var inputFocused: Bool

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }

    var body: some View {
        GameScaffold(mode: mode, trainTitle: "Number Memory",
                     trainBest: PersonalBestTracker.shared.best(for: .sequentialMemory) > 0 ? "\(PersonalBestTracker.shared.best(for: .sequentialMemory))" : nil,
                     glow: Color(red: 0.03, green: 0.16, blue: 0.16)) {
            phaseContent
        }
    }

    private var phaseContent: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .setup:
                setupView
                    .transition(.opacity)
            case .showing:
                showingView
                    .transition(.opacity)
            case .input:
                inputView
                    .transition(.opacity)
            case .roundResult:
                roundResultView
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            case .finished:
                if mode.run != nil { Color.clear } else {
                    resultsView
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .sheet(isPresented: $showingPaywall) { PaywallView(isHighIntent: true) }
        .navigationTitle("Number Memory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let run = mode.run {
                viewModel.onLevelCleared = { run.report(score: $0) }
            }
            if autoStart && viewModel.phase == .setup {
                Analytics.exerciseStarted(game: ExerciseType.sequentialMemory.rawValue)
                viewModel.startGame()
            }
        }
        .onDisappear {
            if viewModel.phase != .setup && viewModel.phase != .finished {
                Analytics.exerciseAbandoned(game: ExerciseType.sequentialMemory.rawValue, roundReached: viewModel.round)
            }
        }
        .onChange(of: mode.run?.isFrozen ?? false) { _, frozen in
            viewModel.holdAdvance = frozen
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .roundResult {
                if let last = viewModel.roundResults.last {
                    if last.correct {
                        correctPulse = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { correctPulse = false }
                    } else {
                        withAnimation(.default) { shakeAmount += 1 }
                    }
                }
            }
            if newPhase == .finished {
                GameSound.complete()
                isNewPersonalBest = PersonalBestTracker.shared.record(score: viewModel.maxCorrectLength, for: .sequentialMemory)
                if isNewPersonalBest {
                    Analytics.personalBest(game: ExerciseType.sequentialMemory.rawValue, score: viewModel.maxCorrectLength)
                }
                AdaptiveDifficultyEngine.shared.recordBlock(domain: .sequentialMemory, correct: viewModel.correctRounds, total: viewModel.roundResults.count)
                // Auto-save so GC gets the score even if user doesn't tap Done
                saveExercise()
                mode.run?.finish(finalScore: viewModel.maxCorrectLength)
                let card = ExerciseShareCard(
                    exerciseName: "Number Memory",
                    exerciseIcon: "number.circle.fill",
                    accentColor: AppColors.teal,
                    mainValue: "\(viewModel.maxCorrectLength)",
                    mainLabel: "Digit Span",
                    ratingText: viewModel.maxCorrectLength >= 9 ? "Genius" : viewModel.maxCorrectLength >= 7 ? "Excellent" : viewModel.maxCorrectLength >= 5 ? "Good" : "Keep Training",
                    stats: [
                        ("Rounds Passed", "\(viewModel.roundResults.filter(\.correct).count)")
                    ],
                    ctaText: "Beat my memory"
                )
                shareImage = card.renderAsImage(size: CGSize(width: 360, height: 640), scale: 3)
            }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        GameIntro(
            game: .numberMemory,
            subtitle: "Remember the number.",
            steps: [
                (icon: "eye.fill", text: "Watch each digit appear"),
                (icon: "keyboard.fill", text: "Type the whole number"),
                (icon: "arrow.up.right", text: "It grows one digit each round"),
            ],
            onStart: {
                Analytics.exerciseStarted(game: ExerciseType.sequentialMemory.rawValue)
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
            ExerciseInfoSheet(type: .sequentialMemory)
                .presentationDetents([.medium])
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Showing Digits

    private var showingView: some View {
        GeometryReader { geo in
            let digits = viewModel.currentLength
            let size = min(64, (geo.size.width - 48) / (CGFloat(digits) * 0.62))
            VStack(spacing: 10) {
                Spacer()
                Text(viewModel.targetNumber)
                    .font(HeroNumber.font(size))
                    .tracking(4)
                    .foregroundStyle(LinearGradient.hero(Color(red: 0.5, green: 0.9, blue: 0.82)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(digits) DIGITS")
                    .font(.brand(size: 12, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(OB.fg3)
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(showStartedAt)
                    let left = max(0, 1 - elapsed / viewModel.displayDuration)
                    Capsule().fill(.white.opacity(0.1)).frame(width: 200, height: 5)
                        .overlay(alignment: .leading) { Capsule().fill(Color(red: 0.18, green: 0.83, blue: 0.75)).frame(width: 200 * left, height: 5) }
                }
                .padding(.top, 8)
                Spacer()
                Text("memorize…")
                    .font(.brand(size: 13, weight: .heavy))
                    .foregroundStyle(OB.fg3)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { showStartedAt = Date() }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: 10) {
            AnswerBoxes(entry: viewModel.userInput, length: viewModel.currentLength, tint: Color(red: 0.18, green: 0.83, blue: 0.75), flash: .idle)
                .padding(.horizontal, 16)
                .padding(.top, 60)
            Text("WHAT WAS IT?")
                .font(.brand(size: 12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(OB.fg3)
            
            Spacer()
            BevelKeypad(onDigit: { viewModel.type($0) }, onDelete: { viewModel.deleteDigit() })
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .modifier(ShakeEffect(animatableData: shakeAmount))
    }

    // MARK: - Round Result

    private var roundResultView: some View {
        VStack(spacing: 10) {
            AnswerBoxes(entry: viewModel.userInput, length: viewModel.currentLength, tint: Color(red: 0.18, green: 0.83, blue: 0.75), flash: viewModel.lastAnswerCorrect ? .correct : .wrong)
                .padding(.horizontal, 16)
                .padding(.top, 60)
            Text("WHAT WAS IT?")
                .font(.brand(size: 12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(OB.fg3)
            if !viewModel.lastAnswerCorrect {
                Text(viewModel.targetNumber)
                    .font(HeroNumber.font(22)).tracking(3)
                    .foregroundStyle(OB.fg2)
            }
            Spacer()
            BevelKeypad(onDigit: { viewModel.type($0) }, onDelete: { viewModel.deleteDigit() })
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .modifier(ShakeEffect(animatableData: shakeAmount))
        .overlay { PraisePop(text: viewModel.lastAnswerCorrect ? "PERFECT!" : nil, tint: Color(red: 0.18, green: 0.83, blue: 0.75)) }
    }

    // MARK: - Final Results

    private var resultsView: some View {
        return GameResultView(
            gameTitle: "Number Memory",
            gameIcon: "number.circle.fill",
            accentColor: AppColors.teal,
            mainScore: viewModel.maxCorrectLength,
            scoreLabel: "DIGITS",
            ratingText: viewModel.maxCorrectLength >= 9 ? "Genius!" : viewModel.maxCorrectLength >= 7 ? "Excellent!" : viewModel.maxCorrectLength >= 5 ? "Good!" : "Keep Training!",
            stats: [
                (label: "Max Digit Span", value: "\(viewModel.maxCorrectLength)"),
                (label: "Rounds Passed", value: "\(viewModel.roundResults.filter(\.correct).count)")
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: PersonalBestTracker.shared.best(for: .sequentialMemory),
            exerciseType: .sequentialMemory,
            leaderboardScore: viewModel.maxCorrectLength,
            onPlayAgain: {
                exerciseSaved = false
                viewModel.reset()
                viewModel.startGame()
            },
            onDone: {
                saveExercise()
                dismiss()
            }
        )
    }

    private func generateShareCard() {
        guard let image = shareImage else { return }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    // MARK: - Save

    private func saveExercise() {
        guard !exerciseSaved else { return }
        exerciseSaved = true
        paywallTrigger.recordExerciseCompleted(gameType: .sequentialMemory)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        GameResultRecorder.record(
            type: .sequentialMemory,
            accuracy: viewModel.score,
            difficulty: viewModel.maxCorrectLength,
            durationSeconds: viewModel.durationSeconds,
            leaderboardScore: viewModel.maxCorrectLength,
            user: user,
            modelContext: modelContext,
            gameCenter: gameCenterService
        )
    }
}
