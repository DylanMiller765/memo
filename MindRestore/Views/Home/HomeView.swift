import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreService.self) private var storeService
    @Environment(TrainingSessionManager.self) private var trainingManager
    @Environment(PaywallTriggerService.self) private var paywallTrigger
    @Environment(GameCenterService.self) private var gameCenterService
    @Query private var users: [User]
    @Query(sort: \DailySession.date, order: .reverse) private var sessions: [DailySession]
    @Query private var exercises: [Exercise]

    @Binding var selectedTab: Int
    @State private var viewModel = HomeViewModel()
    @State private var showingPaywall = false
    @State private var showingFreezeInfo = false
    @State private var cachedTodayExerciseCount: Int = 0
    @State private var weeklyRank: Int?

    init(selectedTab: Binding<Int>) {
        _selectedTab = selectedTab
        var recentExercises = FetchDescriptor<Exercise>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        recentExercises.fetchLimit = 50
        _exercises = Query(recentExercises)
    }

    private var user: User? { users.first }
    private var isNewUser: Bool { sessions.count <= 1 && exercises.count < 3 }

    private func lastPlayedText(for type: ExerciseType) -> String? {
        guard let lastExercise = exercises.first(where: { $0.type == type }) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastExercise.completedAt, to: .now).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }

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
                VStack(spacing: 10) {
                    // Compact header: greeting + streak + level
                    compactHeader
                        .staggeredEntrance(index: 0)

                    // Mascot Hero — dominates the screen
                    mascotHeroSection
                        .staggeredEntrance(index: 1)

                    // Focus Mode card
                    FocusModeCard()
                        .staggeredEntrance(index: 2)

                    // Streak Week Calendar
                    streakWeekCard
                        .staggeredEntrance(index: 6)

                    if isNewUser {
                        getStartedCard
                            .staggeredEntrance(index: 7)
                    } else {
                        TrainingPaceBanner(trainingMinutes: trainingManager.todayTrainingMinutes)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 0)
                .padding(.bottom, 128)
                .responsiveContent()
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onAppear {
                viewModel.refresh(user: user, sessions: sessions)
                refreshTodayExerciseCount()
            }
            .onChange(of: exercises.count) {
                refreshTodayExerciseCount()
            }
            .task { weeklyRank = await gameCenterService.bestWeeklyRank() }
        }
    }

    // MARK: - Mascot Hero Section

    private var todayExerciseCount: Int { cachedTodayExerciseCount }

    private func refreshTodayExerciseCount() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        cachedTodayExerciseCount = exercises.filter { $0.completedAt >= startOfDay }.count
    }

    private var mascotMood: MascotRiveMood {
        // 3+ games today = happy
        if todayExerciseCount >= 3 {
            return .happy
        }
        // Haven't played recently = sad
        if let lastSession = user?.lastSessionDate,
           !Calendar.current.isDateInToday(lastSession),
           !Calendar.current.isDateInYesterday(lastSession) {
            return .sad
        }
        // Default: neutral (start of day, or <3 games)
        return .neutral
    }

    private var mascotMoodText: String {
        switch mascotMood {
        case .happy:
            return "Memo is locked in today"
        case .neutral:
            let remaining = 3 - todayExerciseCount
            if remaining == 1 {
                return "One more rep to lock in"
            } else if remaining == 2 {
                return "Train 3 times to lock in"
            }
            return "Memo needs reps today"
        case .sad:
            return "Memo needs reps today"
        }
    }

    private var mascotMoodColor: Color {
        switch mascotMood {
        case .happy: return AppColors.teal
        case .neutral: return AppColors.amber
        case .sad: return AppColors.coral
        }
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .mainScreenTitleStyle(size: 30, lineLimit: 2, minimumScaleFactor: 0.72)
                if let weeklyRank {
                    Text("#\(weeklyRank) this week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Streak flame badge
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .symbolEffect(.bounce, value: viewModel.currentStreak)
                    .foregroundStyle(viewModel.currentStreak > 0 ? streakGradient : AnyShapeStyle(.secondary))
                Text("\(viewModel.currentStreak)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Mascot Hero Section

    private var mascotHeroSection: some View {
        VStack(spacing: 6) {
            // Daily training state: sad/neutral/happy based on today's reps.
            RiveMascotView(
                mood: mascotMood,
                size: 250
            )
            .frame(height: 210)

            // Mood text
            Text(mascotMoodText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(mascotMoodColor)
                .multilineTextAlignment(.center)

            // Progress dots — 3 games to make mascot happy
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < todayExerciseCount ? AppColors.accent : AppColors.accent.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .scaleEffect(i < todayExerciseCount ? 1.0 : 0.8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: todayExerciseCount)
                }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily training progress")
            .accessibilityValue("\(min(todayExerciseCount, 3)) of 3 games completed")
        }
        .padding(.top, 0)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streak Week Calendar Card

    private var streakGradient: AnyShapeStyle {
        let streak = viewModel.currentStreak
        if streak >= 30 {
            return AnyShapeStyle(LinearGradient(colors: [.blue, .white], startPoint: .bottom, endPoint: .top))
        } else if streak >= 14 {
            return AnyShapeStyle(LinearGradient(colors: [.red, .purple], startPoint: .bottom, endPoint: .top))
        } else if streak >= 7 {
            return AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .bottom, endPoint: .top))
        } else {
            return AnyShapeStyle(.orange)
        }
    }

    private var streakWeekCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .symbolEffect(.bounce, value: viewModel.currentStreak)
                        .foregroundStyle(viewModel.currentStreak > 0 ? streakGradient : AnyShapeStyle(.secondary))
                    Text("\(viewModel.currentStreak) day streak")
                        .font(.headline.weight(.bold))
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(viewModel.currentStreak) day streak")

                Spacer()

                if viewModel.longestStreak > 0 {
                    Text("Best: \(viewModel.longestStreak)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            StreakWeekView(
                sessions: sessions.map(\.date),
                currentStreak: viewModel.currentStreak
            )

            if user?.isStreakActive != true {
                Text("Complete an exercise today to keep your streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(viewModel.currentStreak > 0 ? AppColors.coral.opacity(0.06) : AppColors.cardSurface)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
    }

    // MARK: - Get Started Card (New Users)

    private var getStartedCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Training")
                        .font(.headline.weight(.bold))
                    Text("Complete your first exercise to begin tracking progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                selectedTab = 1
            } label: {
                Text("Go to Exercises")
                    .gradientButton()
            }
        }
        .padding(20)
        .glowingCard(color: AppColors.accent, intensity: 0.15)
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
