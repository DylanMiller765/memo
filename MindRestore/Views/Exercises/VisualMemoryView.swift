import SwiftUI
import SwiftData
import GameKit

// MARK: - ViewModel

@MainActor @Observable
final class VisualMemoryViewModel {
    enum Phase { case setup, showing, input, correct, wrongReveal, finished }

    var phase: Phase = .setup
    var startTime: Date?
    var level = 1
    var highlightedCells: Set<Int> = []
    var selectedCells: Set<Int> = []
    var gridSize: Int = 4
    var highlightCount: Int = 3
    var challengeSeed: Int?
    private var rng: SeededGenerator?
    private var showTimer: Timer?
    var levelsCompleted = 0
    var isOnboardingPreview = false

    var score: Double {
        Double(levelsCompleted) / 10.0
    }

    var maxLevelReached: Int {
        levelsCompleted
    }

    var durationSeconds: Int {
        guard let start = startTime else { return 0 }
        return Int(Date.now.timeIntervalSince(start))
    }

    var totalCells: Int {
        gridSize * gridSize
    }

    /// Display time decreases at higher levels (1.5s at level 1, down to 0.6s at level 10)
    private var showDuration: TimeInterval {
        max(0.6, 1.5 - Double(level - 1) * 0.1)
    }

    // Grid grows with the run so strong players never plateau: levels 1-3 =
    // 4x4 (matches onboarding assessment), 4-7 = 5x5, 8-12 = 6x6, 13+ = 7x7.
    // No 3x3 entry tier — Visual Memory is intentionally non-trivial.
    private func updateGridForLevel() {
        switch level {
        case 1...3:
            gridSize = 4
        case 4...7:
            gridSize = 5
        case 8...12:
            gridSize = 6
        default:
            gridSize = 7
        }
        // Highlight count increases each level: starts at 3, +1 per level
        highlightCount = min(2 + level, totalCells - 1)
    }

    func startGame() {
        level = isOnboardingPreview ? 1 : max(1, AdaptiveDifficultyEngine.shared.currentLevel(for: .visualMemory))
        levelsCompleted = 0
        startTime = Date.now
        if let seed = challengeSeed {
            rng = SeededGenerator(seed: UInt64(seed))
        } else {
            rng = nil
        }
        startLevel()
    }

    func startLevel() {
        updateGridForLevel()
        selectedCells = []

        // Pick random cells to highlight
        var cells = Set<Int>()
        while cells.count < highlightCount {
            if var r = rng {
                cells.insert(Int.random(in: 0..<totalCells, using: &r))
                rng = r
            } else {
                cells.insert(Int.random(in: 0..<totalCells))
            }
        }
        highlightedCells = cells

        // Show the pattern
        phase = .showing
        SoundService.shared.playTap()

        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: showDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.phase = .input
            }
        }
    }

    func toggleCell(_ index: Int) {
        guard phase == .input else { return }
        if selectedCells.contains(index) {
            selectedCells.remove(index)
        } else {
            selectedCells.insert(index)
        }
        HapticService.tap()
    }

    func submit() {
        guard phase == .input else { return }

        if selectedCells == highlightedCells {
            // Correct — advance straight to the next level. No "Passed Level X"
            // interstitial — the next level's squares flashing IS the success
            // signal, and the haptic + sound register the win without burning
            // a second on a green-checkmark screen.
            levelsCompleted = level
            HapticService.correct()
            HapticService.levelUp()
            level += 1
            startLevel()
        } else {
            // Wrong — show correct answer, then game over. Haptic only: the
            // system "horn" buzzer reads as cheap, the wrong-answer haptic
            // already carries the moment.
            HapticService.wrong()
            phase = .wrongReveal
            showTimer?.invalidate()
            showTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.phase = .finished
                }
            }
        }
    }

    func reset() {
        showTimer?.invalidate()
        phase = .setup
    }

    var ratingText: String {
        let lvl = maxLevelReached
        if lvl >= 10 { return "Perfect Memory!" }
        if lvl >= 8 { return "Excellent!" }
        if lvl >= 6 { return "Great Job!" }
        if lvl >= 4 { return "Good!" }
        if lvl >= 2 { return "Not Bad!" }
        return "Keep Practicing!"
    }
}

// MARK: - View

struct VisualMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AchievementService.self) private var achievementService
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(StoreService.self) private var storeService
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query private var users: [User]

    /// When true, skip the setup screen on appear and jump straight into the
    /// game after a brief "get ready" overlay. Used for Focus unlock launches
    /// where the user already pressed "Train" — landing on a Tap-to-Begin
    /// screen is one step too many.
    var autoStart: Bool = false
    var isOnboardingPreview: Bool = false
    var onPreviewComplete: (() -> Void)? = nil
    var onPreviewProgress: ((Int) -> Void)? = nil

    @State private var viewModel = VisualMemoryViewModel()
    @State private var showingPaywall = false
    @State private var isNewPersonalBest = false
    @State private var shareImage: UIImage?
    @State private var exerciseSaved = false
    @State private var shakeAmount: CGFloat = 0
    @State private var correctPulse = false
    @State private var showingInfo = false

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .setup:
                setupView
                    .transition(.opacity)
            case .showing:
                gameView(interactable: false)
                    .transition(.opacity)
            case .input:
                gameView(interactable: true)
                    .transition(.opacity)
            case .correct:
                correctView
                    .transition(.opacity)
            case .wrongReveal:
                wrongRevealView
                    .transition(.opacity)
            case .finished:
                if isOnboardingPreview {
                    previewResultView
                        .transition(.opacity)
                } else {
                    resultsView
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase == .finished)
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase == .correct)
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase == .wrongReveal)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .navigationTitle("Visual Memory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if autoStart && viewModel.phase == .setup {
                viewModel.isOnboardingPreview = isOnboardingPreview
                if !isOnboardingPreview {
                    Analytics.exerciseStarted(game: ExerciseType.visualMemory.rawValue)
                }
                viewModel.startGame()
            }
        }
        .onDisappear {
            if isOnboardingPreview {
                viewModel.reset()
            } else if viewModel.phase != .setup && viewModel.phase != .finished {
                Analytics.exerciseAbandoned(game: ExerciseType.visualMemory.rawValue, roundReached: viewModel.level)
            }
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .correct {
                correctPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { correctPulse = false }
            } else if newPhase == .wrongReveal {
                withAnimation(.default) { shakeAmount += 1 }
            }
            if newPhase == .finished {
                if isOnboardingPreview {
                    onPreviewComplete?()
                    return
                }
                isNewPersonalBest = PersonalBestTracker.shared.record(score: viewModel.maxLevelReached, for: .visualMemory)
                if isNewPersonalBest {
                    Analytics.personalBest(game: ExerciseType.visualMemory.rawValue, score: viewModel.maxLevelReached)
                }
                AdaptiveDifficultyEngine.shared.recordBlock(domain: .visualMemory, correct: viewModel.maxLevelReached, total: viewModel.level)
                // Auto-save so GC gets the score even if user doesn't tap Done
                saveExercise()
                let card = ExerciseShareCard(
                    exerciseName: "Visual Memory",
                    exerciseIcon: "square.grid.3x3.fill",
                    accentColor: AppColors.indigo,
                    mainValue: "Level \(viewModel.maxLevelReached)",
                    mainLabel: "Max Level",
                    ratingText: viewModel.ratingText,
                    stats: [
                        ("Levels Cleared", "\(viewModel.levelsCompleted)"),
                        ("Time", viewModel.durationSeconds.durationString)
                    ],
                    ctaText: "How far can you get?"
                )
                shareImage = card.renderAsImage(size: CGSize(width: 360, height: 640), scale: 3)
            }
        }
        .onChange(of: viewModel.levelsCompleted) { _, newValue in
            if isOnboardingPreview && newValue > 0 { onPreviewProgress?(newValue) }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 32) {
            Spacer()

            TrainingTileMiniPreview(type: .visualMemory, color: AppColors.indigo, scale: 2.0)
                .frame(width: 200, height: 140)

            VStack(spacing: 8) {
                Text("Visual Memory")
                    .font(.title.weight(.bold))
                Text("Remember the pattern")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                infoRow(icon: "eye.fill", text: "Memorize which squares light up")
                infoRow(icon: "hand.tap.fill", text: "Tap to recreate the pattern")
                infoRow(icon: "exclamationmark.triangle.fill", text: "One mistake and it's over!")
            }
            .appCard()
            .padding(.horizontal)

            Spacer()

            Button {
                Analytics.exerciseStarted(game: ExerciseType.visualMemory.rawValue)
                viewModel.startGame()
            } label: {
                Text("Start")
                    .accentButton()
            }
            .pulsingWhenIdle()
            .accessibilityHint("Starts the exercise")
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
        .overlay(alignment: .topTrailing) {
            Button { showingInfo = true } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
        }
        .sheet(isPresented: $showingInfo) {
            ExerciseInfoSheet(type: .visualMemory)
                .presentationDetents([.medium])
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.violet)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Game View

    private func gameView(interactable: Bool) -> some View {
        let compactPreview = isOnboardingPreview && UIScreen.main.bounds.height < 700
        return VStack(spacing: compactPreview ? 9 : 20) {
            // Header
            Text("Level \(viewModel.level)")
                .font(.headline)
                .foregroundStyle(AppColors.accent)
                .contentTransition(.numericText())
                .padding(.horizontal)

            // Grid size indicator
            Text("\(viewModel.gridSize)x\(viewModel.gridSize) Grid")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if !interactable {
                Text("Memorize!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.violet)
            } else {
                Text("Tap the squares (\(viewModel.selectedCells.count)/\(viewModel.highlightCount))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if !compactPreview { Spacer() }

            // Grid — tighter gutters once the grid passes 5x5 so cells stay tappable.
            let cellSpacing: CGFloat = viewModel.gridSize >= 6 ? 6 : 8
            let columns = Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: viewModel.gridSize)
            LazyVGrid(columns: columns, spacing: cellSpacing) {
                ForEach(0..<viewModel.totalCells, id: \.self) { index in
                    gridCell(index: index, interactable: interactable)
                }
            }
            .frame(maxWidth: compactPreview ? (viewModel.gridSize >= 6 ? 300 : 228) : .infinity)
            .padding(.horizontal, compactPreview ? 0 : 32)

            if !compactPreview { Spacer() }

            // Always reserve space for button so grid doesn't shift between phases
            Button {
                viewModel.submit()
            } label: {
                Text("Submit")
                    .accentButton()
            }
            .disabled(!interactable || viewModel.selectedCells.count != viewModel.highlightCount)
            .opacity(interactable && viewModel.selectedCells.count == viewModel.highlightCount ? 1.0 : interactable ? 0.5 : 0)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, compactPreview ? 8 : 24)
        .modifier(ShakeEffect(animatableData: shakeAmount))
        .scaleEffect(correctPulse ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: correctPulse)
    }

    @ViewBuilder
    private func gridCell(index: Int, interactable: Bool) -> some View {
        let isHighlighted = viewModel.highlightedCells.contains(index)
        let isSelected = viewModel.selectedCells.contains(index)

        RoundedRectangle(cornerRadius: 10)
            .fill(cellFill(isHighlighted: isHighlighted, isSelected: isSelected, interactable: interactable))
            .aspectRatio(1, contentMode: .fit)
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onTapGesture {
                if interactable {
                    viewModel.toggleCell(index)
                }
            }
            .accessibilityLabel("Cell \(index + 1)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cellFill(isHighlighted: Bool, isSelected: Bool, interactable: Bool) -> some ShapeStyle {
        if !interactable && isHighlighted {
            return AnyShapeStyle(AppColors.accent)
        } else if interactable && isSelected {
            return AnyShapeStyle(AppColors.accent)
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.12))
        }
    }


    // MARK: - Correct

    private var correctView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.cardBorder)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.mint)
            }

            Text("Level \(viewModel.level) Complete!")
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())

            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Wrong Reveal

    private var wrongRevealView: some View {
        VStack(spacing: 20) {
            Text("Wrong!")
                .font(.title.weight(.bold))
                .foregroundStyle(AppColors.coral)

            Text("The correct pattern was:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: viewModel.gridSize)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<viewModel.totalCells, id: \.self) { index in
                    let isCorrect = viewModel.highlightedCells.contains(index)
                    let wasSelected = viewModel.selectedCells.contains(index)

                    RoundedRectangle(cornerRadius: 10)
                        .fill(revealCellColor(isCorrect: isCorrect, wasSelected: wasSelected))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if wasSelected && !isCorrect {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                }
            }
            .padding(.horizontal, 32)

            Text("Level \(viewModel.levelsCompleted)")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func revealCellColor(isCorrect: Bool, wasSelected: Bool) -> Color {
        if isCorrect && wasSelected {
            return AppColors.mint // got it right
        } else if isCorrect {
            return AppColors.accent // missed this one
        } else if wasSelected {
            return AppColors.coral.opacity(0.7) // wrong pick
        } else {
            return Color.gray.opacity(0.12)
        }
    }

    // MARK: - Results

    private var previewResultView: some View {
        VStack(spacing: 16) {
            Spacer()
            TrainingTileMiniPreview(type: .visualMemory, color: AppColors.indigo, scale: 1.7)
                .frame(width: 180, height: 130)
            Text(viewModel.levelsCompleted > 0 ? "Pattern remembered." : "That's the game.")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("A full game earns the unlock time shown on the slot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var resultsView: some View {
        return GameResultView(
            gameTitle: "Visual Memory",
            gameIcon: "square.grid.3x3.fill",
            accentColor: AppColors.indigo,
            mainScore: viewModel.maxLevelReached,
            scoreLabel: "LEVEL REACHED",
            ratingText: viewModel.ratingText,
            stats: [
                (label: "Levels Cleared", value: "\(viewModel.levelsCompleted)"),
                (label: "Time", value: viewModel.durationSeconds.durationString)
            ],
            isNewPersonalBest: isNewPersonalBest,
            personalBest: PersonalBestTracker.shared.best(for: .visualMemory),
            exerciseType: .visualMemory,
            leaderboardScore: viewModel.maxLevelReached,
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
        paywallTrigger.recordExerciseCompleted(gameType: .visualMemory)
        trainingManager.addTrainingTime(viewModel.durationSeconds)

        let exercise = Exercise(
            type: .visualMemory,
            difficulty: viewModel.maxLevelReached,
            score: viewModel.score,
            durationSeconds: viewModel.durationSeconds
        )
        modelContext.insert(exercise)

        let descriptor = FetchDescriptor<DailySession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allSessions = (try? modelContext.fetch(descriptor)) ?? []
        let session: DailySession
        if let existing = allSessions.first(where: { Calendar.current.isDateInToday($0.date) }) {
            session = existing
        } else {
            session = DailySession()
            modelContext.insert(session)
        }
        session.addExercise(exercise)
        user?.updateStreak()
        NotificationService.shared.cancelStreakRisk()
        if let streak = user?.currentStreak {
            NotificationService.shared.scheduleMilestone(streak: streak)
        }

        if let user {
            _ = ContentView.awardXP(
                user: user,
                score: viewModel.score,
                difficulty: viewModel.maxLevelReached,
                achievementService: achievementService,
                modelContext: modelContext,
                gameCenterService: gameCenterService,
                exerciseType: .visualMemory,
                gameScore: viewModel.maxLevelReached
            )
        }
    }
}
