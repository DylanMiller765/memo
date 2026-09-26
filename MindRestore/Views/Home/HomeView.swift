import SwiftUI
import SwiftData
import DeviceActivity

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(StoreService.self) private var storeService
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(FocusModeService.self) private var focusModeService
    @Query private var users: [User]
    @Query(sort: \DailySession.date, order: .reverse) private var sessions: [DailySession]
    @Query private var exercises: [Exercise]

    @Binding var selectedTab: Int
    @State private var viewModel = HomeViewModel()
    @State private var showingPaywall = false
    @State private var showingFreezeInfo = false
    @State private var cachedTodayExerciseCount: Int = 0
    @State private var weeklyRank: Int?

    // On the hill
    @State private var charge = HomeCharge.make(gamesToday: 0, lastSessionDate: nil, now: .now)
    @State private var payoffFrom: Int?
    @State private var displayedMood: MascotRiveMood = .neutral
    @State private var displayedTier: HomeTier = .dim
    @State private var memoBounce = false
    @State private var showBubble = false
    @State private var bubbleTask: Task<Void, Never>?

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)          // #0B1B22
    private static let tileFill = Color(red: 0, green: 0.086, blue: 0.11).opacity(0.42)
    private static let tileShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    init(selectedTab: Binding<Int>) {
        _selectedTab = selectedTab
        var recentExercises = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        recentExercises.fetchLimit = 50
        _exercises = Query(recentExercises)
    }

    private var user: User? { users.first }

    /// SE-class screens get a smaller Memo so the meter and tiles stay above the fold.
    private var isCompactHeight: Bool { UIScreen.main.bounds.height < 700 }
    private var memoHeight: CGFloat { isCompactHeight ? 170 : 210 }

    private var isRain: Bool { if case .rain = charge.tier { return true } else { return false } }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 17 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }

        if let name = user?.username, !name.isEmpty {
            return "\(timeGreeting), \(name)"
        }
        return timeGreeting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    compactHeader
                        .staggeredEntrance(index: 0)

                    memo
                        .staggeredEntrance(index: 1)

                    HomeChargeMeter(percent: charge.percent, tier: charge.tier, line: charge.line, animateFrom: payoffFrom)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTab = 1 }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens Train")
                        .staggeredEntrance(index: 2)

                    statsRow
                        .padding(.top, 22)
                        .staggeredEntrance(index: 3)

                    FocusModeCard(layout: .hill(isRaining: isRain))
                        .padding(.top, 22)
                        .staggeredEntrance(index: 4)

                    TrainingPaceBanner(trainingMinutes: trainingManager.todayTrainingMinutes)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 128)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .background(alignment: .top) {
                HomeHillScene(tier: displayedTier, crestFromSafeTop: 219 - (210 - memoHeight))
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onAppear {
                viewModel.refresh(user: user, sessions: sessions)
                refreshTodayExerciseCount()
                recomputeCharge()
            }
            // The query is capped at 50, so watch the newest exercise rather than the count.
            .onChange(of: exercises.first?.completedAt) {
                refreshTodayExerciseCount()
                recomputeCharge()
            }
            .onChange(of: scenePhase) { _, phase in
                // Catches midnight rollover while the app sat in the background.
                guard phase == .active else { return }
                refreshTodayExerciseCount()
                recomputeCharge()
            }
            .task { weeklyRank = await gameCenterService.bestWeeklyRank() }
        }
    }

    // MARK: - Charge

    private func refreshTodayExerciseCount() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        cachedTodayExerciseCount = exercises.filter { $0.completedAt >= startOfDay }.count
    }

    private func recomputeCharge() {
        let now = Date.now
        var games = cachedTodayExerciseCount
        var lastSession = user?.lastSessionDate
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let n = Self.debugInt(args, "--home-games") { games = n }
        if let days = Self.debugInt(args, "--home-rain-days") {
            games = 0
            lastSession = Calendar.current.date(byAdding: .day, value: -days, to: now)
        }
        #endif
        let next = HomeCharge.make(gamesToday: games, lastSessionDate: lastSession, now: now)
        charge = next
        payoffFrom = HomeChargeMemory.payoffStart(current: next.percent, now: now, defaults: .standard)

        if let from = payoffFrom, let fromGames = [0, 33, 67, 100].firstIndex(of: from) {
            // Show the old world first, then let the new one fade in once the meter has counted up.
            let before = HomeCharge.make(gamesToday: fromGames, lastSessionDate: lastSession, now: now)
            displayedMood = before.mood
            displayedTier = before.tier
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(850))
                displayedMood = next.mood
                displayedTier = next.tier
            }
        } else {
            displayedMood = next.mood
            displayedTier = next.tier
        }
    }

    /// DEBUG `--home-mood happy|neutral|sad` pins Memo's pose (for checking the Rive poses).
    private var debugMoodOverride: MascotRiveMood? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--home-mood"), args.indices.contains(i + 1) else { return nil }
        return MascotRiveMood(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static func debugInt(_ args: [String], _ flag: String) -> Int? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return Int(args[i + 1])
    }
    #endif

    // MARK: - Header

    private var compactHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.brand(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let weeklyRank {
                    Text("#\(weeklyRank) this week")
                        .font(.brand(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                StickerIcon(kind: .flame, size: 18, muted: viewModel.currentStreak == 0)
                Text("\(viewModel.currentStreak)")
                    .font(.brand(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color(red: 0.04, green: 0.05, blue: 0.16).opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.currentStreak) day streak")
        }
    }

    // MARK: - Memo

    private var memo: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.45))
                .frame(width: 140, height: 22)
                .blur(radius: 4)
                .offset(y: -4)

            RiveMascotView(mood: debugMoodOverride ?? displayedMood, size: isCompactHeight ? 190 : 230, playbackPolicy: .continuous)
                .frame(height: memoHeight)
                .scaleEffect(memoBounce ? 1.08 : 1, anchor: .bottom)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: memoBounce)
                .contentShape(Rectangle())
                .onTapGesture(perform: tapMemo)
                .accessibilityElement()
                .accessibilityLabel("Memo")
                .accessibilityHint(charge.line)
                .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            if showBubble {
                Text(charge.line)
                    .font(.brand(size: 14, weight: .bold))
                    .foregroundStyle(Self.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 2))
                    .offset(y: -6)
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
            }
        }
    }

    private func tapMemo() {
        HapticService.tap()
        memoBounce = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showBubble = true }
        bubbleTask?.cancel()
        bubbleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            memoBounce = false
            try? await Task.sleep(for: .milliseconds(2320))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showBubble = false }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        GeometryReader { geo in
            let tile = (geo.size.width - 20) / 3
            HStack(spacing: 10) {
                Group {
                    if showsDemoStats {
                        HStack(spacing: 10) {
                            homeTile(.clock, value: "6h 02m", label: "Screen time")
                            homeTile(.phone, value: "58", label: "Pickups")
                        }
                    } else if focusModeService.authorizationStatus == .approved {
                        DeviceActivityReport(.homeStats, filter: todayFilter)
                    } else {
                        connectTile
                    }
                }
                .frame(width: tile * 2 + 10)

                homeTile(.padlock, value: formatMinutes(focusModeService.dailyBlockedMinutes), label: "Protected")
                    .frame(width: tile)
            }
        }
        .frame(height: 116)
    }

    private var showsDemoStats: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--screenshot-mode") && args.contains("--home-demo-blocking")
        #else
        return false
        #endif
    }

    private func homeTile(_ kind: StickerKind, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            StickerIcon(kind: kind, size: 40)
            Text(value)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.tileFill, in: Self.tileShape)
        .overlay(Self.tileShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var connectTile: some View {
        Button {
            Task { await focusModeService.requestAuthorization() }
        } label: {
            HStack(spacing: 12) {
                StickerIcon(kind: .hourglass, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Screen Time")
                        .font(.brand(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("See today's time and pickups")
                        .font(.brand(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.tileFill, in: Self.tileShape)
            .overlay(Self.tileShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .contentShape(Self.tileShape)
        }
        .buttonStyle(.plain)
    }

    /// Today's Screen Time, for the report tiles.
    private var todayFilter: DeviceActivityFilter {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: todayStart, end: Date.now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m)m" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }
}

// MARK: - Education Card View (Horizontal)

struct EducationCardView: View {
    let card: PsychoEducationCard

    private var cardColor: Color {
        switch card.category {
        case .socialMedia: return AppColors.coral
        case .cannabis: return AppColors.mint
        case .sleep: return AppColors.indigo
        case .neuroplasticity: return AppColors.violet
        case .techniques: return AppColors.teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColoredIconBadge(icon: card.category.icon, color: cardColor, size: 36)

            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(card.category.displayName)
                .font(.caption)
                .foregroundStyle(cardColor)
        }
        .frame(width: 160, alignment: .leading)
        .glowingCard(color: cardColor, intensity: 0.15)
    }
}

#if DEBUG
#Preview("Home") {
    MainScreenPreview {
        HomeView(selectedTab: .constant(0))
    }
}
#endif
