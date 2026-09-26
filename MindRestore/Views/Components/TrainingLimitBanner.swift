import SwiftUI
import SwiftData

/// A banner that nudges users about optimal training duration.
///
/// - At 15-19 min: encouraging "sweet spot" message (Lampit 2014).
/// - At 20+ min: rest prompt explaining diminishing returns, with a dismiss action.
struct TrainingPaceBanner: View {
    let trainingMinutes: Double
    var onDoneForToday: (() -> Void)?

    @State private var appeared = false

    var body: some View {
        Group {
            if trainingMinutes >= 20 {
                restBanner
            } else if trainingMinutes >= 15 {
                sweetSpotBanner
            }
        }
    }

    // MARK: - Sweet Spot Banner (15-19 min)

    private var sweetSpotBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "brain.fill")
                .font(.title2)
                .foregroundStyle(AppColors.accent)
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 4) {
                Text("You're in the sweet spot!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Science says 15-20 min is optimal for memory training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accent.opacity(0.15), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Rest Banner (20+ min)

    private var restBanner: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.teal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Great session!")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Research shows diminishing returns beyond 20 minutes. Your brain needs rest to consolidate what you learned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let onDoneForToday {
                Button(action: onDoneForToday) {
                    Text("Done for Today")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            AppColors.teal,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .foregroundStyle(.white)
                }
            }
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.teal.opacity(0.15), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Sweet Spot") {
    TrainingPaceBanner(trainingMinutes: 16)
        .padding()
        .pageBackground()
}

#Preview("Training Target") {
    TrainingPaceBanner(trainingMinutes: 22) {
        print("Done tapped")
    }
    .padding()
    .pageBackground()
}

// MARK: - Training View

struct TrainingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query private var users: [User]
    @Query private var exercises: [Exercise]

    /// External trigger for focus unlock — set by ContentView to navigate to a specific game
    @Binding var externalExercise: ExerciseType?
    /// When the external trigger fires, indicates the game should skip its setup screen.
    /// Captured into `pendingAutoStart` on the externalExercise transition; the binding
    /// is reset to false immediately to keep ContentView's source-of-truth clean.
    @Binding var externalExerciseAutoStart: Bool

    @State private var showingPaywall = false
    @State private var selectedExercise: ExerciseType?
    @State private var pendingAutoStart = false

    init(
        externalExercise: Binding<ExerciseType?>,
        externalExerciseAutoStart: Binding<Bool>
    ) {
        _externalExercise = externalExercise
        _externalExerciseAutoStart = externalExerciseAutoStart
        var recentExercises = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        recentExercises.fetchLimit = 20
        _exercises = Query(recentExercises)
    }

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }

    private func lastPlayedText(for type: ExerciseType) -> String? {
        guard let lastExercise = exercises.first(where: { $0.type == type }) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastExercise.completedAt, to: .now).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MainScreenTitle(text: "Train")
                        .padding(.horizontal, 16)
                        .staggeredEntrance(index: 0)

                    // Six games, same glyphs as the slot reel
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(TrainingGameCatalog.focusUnlockGames) { game in
                            if let unlockGame = UnlockGame(exerciseType: game.type) {
                                Button {
                                    selectedExercise = game.type
                                } label: {
                                    TrainGameCard(game: unlockGame, lastPlayedText: lastPlayedText(for: game.type))
                                }
                                .buttonStyle(GameCardButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .staggeredEntrance(index: 1)
                }
                .navigationDestination(item: $selectedExercise) { type in
                    exerciseDestination(for: type)
                        // Clear the auto-start flag once the destination owns it.
                        // Defers to onAppear so the destination's init has already
                        // consumed pendingAutoStart for ReactionTime; subsequent
                        // navigations to any game start with a clean flag.
                        .onAppear { pendingAutoStart = false }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: externalExercise) { _, newValue in
                if let game = newValue {
                    pendingAutoStart = externalExerciseAutoStart
                    selectedExercise = game
                    externalExercise = nil
                    externalExerciseAutoStart = false
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    isHighIntent: true,
                    currentStreak: user?.currentStreak ?? 0,
                    gamesPlayedToday: paywallTrigger.exercisesToday
                )
            }
            .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
                if case .game(let type) = destination {
                    deepLinkRouter.pendingDestination = nil
                    // Pop back first if already in a game, then push the new one
                    if selectedExercise != nil {
                        selectedExercise = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            selectedExercise = type
                        }
                    } else {
                        selectedExercise = type
                    }
                }
            }
        }
    }

    /// Games already carry their own intro screens — they just showed them on
    /// every play. `autoStart` skips straight to the challenge, so replayers
    /// get the game and first-timers get the explanation. Every launch path
    /// resolves through here, so this covers the Train tab and focus unlock.
    private func skipIntro(for type: ExerciseType) -> Bool {
        pendingAutoStart || ExerciseFirstRun.hasPlayed(type)
    }

    @ViewBuilder
    private func exerciseDestination(for type: ExerciseType) -> some View {
        exerciseGame(for: type)
            .onAppear { ExerciseFirstRun.markPlayed(type) }
    }

    @ViewBuilder
    private func exerciseGame(for type: ExerciseType) -> some View {
        switch type {
        case .reactionTime:
            ReactionTimeView(autoStart: skipIntro(for: type))
        case .sequentialMemory:
            SequentialMemoryView(autoStart: skipIntro(for: type))
        case .mathSpeed:
            MathSpeedView(autoStart: skipIntro(for: type))
        case .colorMatch:
            ColorMatchView(autoStart: skipIntro(for: type))
        case .visualMemory:
            VisualMemoryView(autoStart: skipIntro(for: type))
        case .chimpTest:
            ChimpTestView(autoStart: skipIntro(for: type))
        default:
            EmptyView()
        }
    }

}

// MARK: - Training Tile (Game-style grid card)

/// Train-tab card: the slot's game glyph, the game's name, and your best.
struct TrainGameCard: View {
    let game: UnlockGame
    let lastPlayedText: String?

    private var bestText: String? { game.personalBest.map { "Best \(game.scoreText($0))" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GameGlyph(game: game, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.brand(size: 16, weight: .black))
                    .foregroundStyle(OB.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text([bestText, lastPlayedText].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "New")
                    .font(.brand(size: 12, weight: .bold))
                    .foregroundStyle(bestText == nil && lastPlayedText == nil ? OB.accent : OB.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                OB.surface
                RadialGradient(colors: [game.glyphTint.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct TrainingTileMiniPreview: View {
    let type: ExerciseType
    let color: Color
    var scale: CGFloat = 1.0

    private var bgOpacity: Double { scale > 1.0 ? 0.0 : 1.0 }

    var body: some View {
        ZStack {
            previewContent
                .scaleEffect(scale)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        ZStack {
            switch type {
            case .reactionTime:
                // Lightning bolt target
                ZStack {
                    color.opacity(0.08 * bgOpacity)
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }

            case .colorMatch:
                // Stroop color words
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    VStack(spacing: 3) {
                        Text("RED")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.sky)
                        Text("BLUE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.coral)
                        Text("GREEN")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.amber)
                    }
                }

            case .speedMatch:
                // Two cards matching
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.15))
                            .frame(width: 30, height: 36)
                            .overlay(
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(color)
                            )
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.15))
                            .frame(width: 30, height: 36)
                            .overlay(
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(color)
                            )
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .offset(x: 22, y: -14)
                }

            case .visualMemory:
                // Mini grid with highlighted cells
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 4), spacing: 3) {
                        ForEach(0..<16, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill([2, 5, 7, 10, 13].contains(i) ? color : color.opacity(0.12))
                                .frame(height: 14)
                        }
                    }
                }

            case .sequentialMemory:
                // Number sequence
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    HStack(spacing: 4) {
                        ForEach(["3", "8", "1", "5"], id: \.self) { digit in
                            Text(digit)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(color)
                                .frame(width: 24, height: 28)
                                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }

            case .mathSpeed:
                // Math equation
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    VStack(spacing: 4) {
                        Text("7 × 8")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        HStack(spacing: 6) {
                            ForEach(["54", "56", "58"], id: \.self) { ans in
                                Text(ans)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ans == "56" ? .white : color.opacity(0.6))
                                    .frame(width: 28, height: 20)
                                    .background(
                                        (ans == "56" ? color : color.opacity(0.12)),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                            }
                        }
                    }
                }

            case .dualNBack:
                // 3x3 grid with highlighted cell
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 3), count: 3), spacing: 3) {
                        ForEach(0..<9, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 4 ? color : color.opacity(0.12))
                                .frame(height: 18)
                        }
                    }
                    Text("2")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                        .offset(x: 22, y: -22)
                        .padding(3)
                        .background(color.opacity(0.15), in: Circle())
                }

            case .chunkingTraining:
                // Grouped number chunks
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    HStack(spacing: 8) {
                        ForEach(["482", "917", "35"], id: \.self) { chunk in
                            Text(chunk)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }

            case .wordScramble:
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    HStack(spacing: 3) {
                        ForEach(["B", "R", "A", "I", "N"], id: \.self) { letter in
                            Text(letter)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                                .frame(width: 18, height: 22)
                                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

            case .memoryChain:
                // Mini 4x4 grid with shapes — one cell glowing to show sequence
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    let icons = ["circle.fill", "square.fill", "triangle.fill", "diamond.fill",
                                 "star.fill", "heart.fill", "pentagon.fill", "hexagon.fill",
                                 "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
                                 "star.fill", "heart.fill", "pentagon.fill", "hexagon.fill"]
                    let glowing = [2, 5, 10] // cells that are "highlighted" in sequence
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 4), spacing: 3) {
                        ForEach(0..<16, id: \.self) { i in
                            Image(systemName: icons[i])
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(glowing.contains(i) ? .white : color.opacity(0.5))
                                .frame(width: 14, height: 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(glowing.contains(i) ? color : color.opacity(0.1))
                                )
                        }
                    }
                }

            case .chimpTest:
                // Mini chimp test grid: numbered cells + hidden cells
                let s: CGFloat = 14
                let sp: CGFloat = 3
                let fs: CGFloat = 8
                ZStack {
                    VStack(spacing: sp) {
                        HStack(spacing: sp) {
                            Color.clear.frame(width: s, height: s)
                            Text("1").font(.system(size: fs, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).frame(width: s, height: s)
                                .background(color, in: RoundedRectangle(cornerRadius: 4))
                            Color.clear.frame(width: s, height: s)
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.35)).frame(width: s, height: s)
                        }
                        HStack(spacing: sp) {
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.35)).frame(width: s, height: s)
                            Color.clear.frame(width: s, height: s)
                            Text("2").font(.system(size: fs, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).frame(width: s, height: s)
                                .background(color, in: RoundedRectangle(cornerRadius: 4))
                            Color.clear.frame(width: s, height: s)
                        }
                        HStack(spacing: sp) {
                            Color.clear.frame(width: s, height: s)
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.35)).frame(width: s, height: s)
                            Color.clear.frame(width: s, height: s)
                            Text("3").font(.system(size: fs, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).frame(width: s, height: s)
                                .background(color, in: RoundedRectangle(cornerRadius: 4))
                        }
                        HStack(spacing: sp) {
                            Text("4").font(.system(size: fs, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white).frame(width: s, height: s)
                                .background(color, in: RoundedRectangle(cornerRadius: 4))
                            Color.clear.frame(width: s, height: s)
                            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.35)).frame(width: s, height: s)
                            Color.clear.frame(width: s, height: s)
                        }
                    }
                }

            case .verbalMemory:
                ZStack {
                    color.opacity(0.06 * bgOpacity)
                    VStack(spacing: 2) {
                        Text("seen?")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                        Text("apple")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(color.opacity(0.6))
                    }
                }

            default:
                ZStack {
                    color.opacity(0.08 * bgOpacity)
                    Image(systemName: "brain.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
            }

        }
    }
}

// MARK: - Game Card (horizontal scroll card)

struct GameCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct ExerciseInfoSheet: View {
    let type: ExerciseType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(benefits, id: \.self) { benefit in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "brain.fill")
                                .foregroundStyle(color)
                                .frame(width: 24)
                            Text(benefit)
                                .font(.body)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("What This Trains")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var title: String {
        type.displayName
    }

    private var color: Color {
        switch type {
        case .reactionTime: return AppColors.coral
        case .colorMatch: return AppColors.violet
        case .speedMatch: return AppColors.sky
        case .visualMemory: return AppColors.indigo
        case .sequentialMemory: return AppColors.teal
        case .mathSpeed: return AppColors.amber
        case .dualNBack: return AppColors.sky
        case .chunkingTraining: return AppColors.rose
        case .chimpTest: return AppColors.amber
        case .verbalMemory: return AppColors.violet
        default: return AppColors.accent
        }
    }

    private var benefits: [String] {
        switch type {
        case .reactionTime:
            return [
                "Processing speed — how fast your brain responds to stimuli",
                "Visual reflexes and motor response time",
                "Alertness and sustained attention"
            ]
        case .colorMatch:
            return [
                "Cognitive flexibility — the Stroop effect tests your ability to override automatic responses",
                "Selective attention and impulse control",
                "Processing speed under conflicting information"
            ]
        case .speedMatch:
            return [
                "Processing speed and rapid visual comparison",
                "Short-term visual memory for symbol patterns",
                "Decision-making speed under time pressure"
            ]
        case .visualMemory:
            return [
                "Visuospatial working memory — remembering patterns in space",
                "Spatial recall and mental imagery",
                "Attention to detail and pattern recognition"
            ]
        case .sequentialMemory:
            return [
                "Digit span — a core measure of working memory capacity",
                "Sequential processing and number recall",
                "Concentration and mental rehearsal"
            ]
        case .mathSpeed:
            return [
                "Mental arithmetic and numerical fluency",
                "Processing speed with mathematical operations",
                "Working memory for holding numbers while calculating"
            ]
        case .dualNBack:
            return [
                "Working memory — the gold standard training task backed by research",
                "Dual-task processing (tracking two things simultaneously)",
                "Fluid intelligence and cognitive control"
            ]
        case .chunkingTraining:
            return [
                "Memory chunking — grouping information into meaningful units",
                "Working memory capacity expansion",
                "Pattern recognition in number sequences"
            ]
        case .chimpTest:
            return [
                "Spatial working memory — remembering positions after brief exposure",
                "Based on research with chimpanzee Ayumu at Kyoto University",
                "Visual processing speed and positional recall"
            ]
        case .verbalMemory:
            return [
                "Verbal recognition memory — distinguishing new from familiar words",
                "Long-term encoding and retrieval",
                "Sustained attention over growing word pools"
            ]
        default:
            return ["General brain training"]
        }
    }
}
