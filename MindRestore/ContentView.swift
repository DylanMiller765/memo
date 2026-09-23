import SwiftUI
import SwiftData

extension Notification.Name {
    static let streakMilestoneCelebration = Notification.Name("streakMilestoneCelebration")
    static let brainScoreMilestoneCelebration = Notification.Name("brainScoreMilestoneCelebration")
    static let workoutGameCompleted = Notification.Name("workoutGameCompleted")
    static let brainScoreImproved = Notification.Name("brainScoreImproved")
}

private enum MainTab: Int, CaseIterable {
    case home
    case train
    case compete
    case insights
    case profile

    var analyticsName: String {
        switch self {
        case .home: return "Home"
        case .train: return "Train"
        case .compete: return "Compete"
        case .insights: return "Insights"
        case .profile: return "Profile"
        }
    }
}

/// Owns one-time, nonessential startup work so services do not race from view
/// initializers and repeated appearance callbacks.
@MainActor
@Observable
final class StartupCoordinator {
    private(set) var hasStarted = false

    func start(
        storeService: StoreService,
        gameCenterService: GameCenterService,
        focusModeService: FocusModeService
    ) async -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true

        try? await Task.sleep(for: .milliseconds(100))
        await storeService.startIfNeeded()
        gameCenterService.authenticateIfNeeded()
        await focusModeService.startIfNeeded()
        storeService.scheduleProductPrefetch()
        return true
    }

    func refreshForForeground(focusModeService: FocusModeService) async {
        guard hasStarted else { return }
        await focusModeService.refreshForAppForeground()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var users: [User]
    @Query private var sessions: [DailySession]
    @Query(sort: \BrainScoreResult.date, order: .reverse) private var brainScoreResults: [BrainScoreResult]
    @State private var showOnboarding = false
    @State private var selectedTab: MainTab = .home
    @State private var storeService = StoreService()
    @State private var achievementService = AchievementService()
    @State private var paywallTrigger = PaywallTriggerService()
    @State private var trainingManager = TrainingSessionManager()
    @State private var gameCenterService = GameCenterService()
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var focusModeService = FocusModeService()
    @State private var startupCoordinator = StartupCoordinator()
    #if DEBUG
    @State private var didConfigureScreenshotMode = false
    @State private var showingScreenshotBrainAge = false
    @State private var showingScreenshotFocusSetup = false
    @State private var showingScreenshotHardPaywall = false
    #endif

    @State private var showQuickGame = false
    @State private var focusUnlockPending = false
    @State private var focusUnlockExercise: ExerciseType?
    @State private var focusUnlockExerciseAutoStart = false
    @State private var showingFocusUnlockSlot = false
    @State private var focusUnlockExpectedExercise: ExerciseType?
    @State private var showFocusUnlockToast = false
    /// Minutes granted by the most recent spin payout — feeds the toast.
    @State private var lastUnlockMinutes = 5

    // Toast state
    @State private var showingXPToast = false
    @State private var lastXPGained = 0
    @State private var lastLevelUp = false
    @State private var lastNewLevel: Int?

    // Streak freeze toast state
    @State private var showingStreakFreezeToast = false
    @State private var freezeToastMessage = ""

    // Streak milestone celebration
    @State private var showingStreakCelebration = false
    @State private var celebrationStreak = 0

    // Brain Score milestone celebration
    @State private var showingBrainScoreMilestone = false
    @State private var milestoneBrainScore = 0

    private var user: User? { users.first }

    private var selectedTabIndex: Binding<Int> {
        Binding(
            get: { selectedTab.rawValue },
            set: { selectedTab = MainTab(rawValue: $0) ?? .home }
        )
    }

    var body: some View {
        Group {
            #if DEBUG
            if let onboardingStartPage = screenshotOnboardingStartPage {
                OnboardingView(startPage: onboardingStartPage) {}
            } else if user?.hasCompletedOnboarding == true {
                mainTabView
            } else {
                OnboardingView {
                    withAnimation {
                        showOnboarding = false
                    }
                }
            }
            #else
            if user?.hasCompletedOnboarding == true {
                mainTabView
            } else {
                OnboardingView {
                    withAnimation {
                        showOnboarding = false
                    }
                }
            }
            #endif
        }
        .environment(storeService)
        .environment(achievementService)
        .environment(paywallTrigger)
        .environment(trainingManager)
        .environment(gameCenterService)
        .environment(deepLinkRouter)
        .environment(focusModeService)
        #if DEBUG
        .fullScreenCover(isPresented: $showingScreenshotHardPaywall) {
            PaywallView(
                isHighIntent: true,
                triggerSource: screenshotTargetArgument == "paywall-concise"
                    ? "onboarding_concise" : "onboarding_personalized_plan",
                isHardPaywall: true,
                dailyScreenTimeHours: 50.2 / 7.0,
                onboardingAge: 25,
                onboardingGoalSummary: "hours back",
                screenTimeIsEstimate: false,
                protectTarget: .school,
                feedWinMoment: .lateNight
            )
            .environment(storeService)
        }
        #endif
        .onOpenURL { url in
            deepLinkRouter.handle(url)
        }
        // Notification taps (e.g. the shield "spin to unlock" notification)
        // route here instead of through UIApplication.shared.open.
        .onReceive(NotificationCenter.default.publisher(for: .memoHandleDeepLink)) { note in
            guard let url = note.object as? URL else { return }
            PendingDeepLink.url = nil
            deepLinkRouter.handle(url)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await startupCoordinator.refreshForForeground(focusModeService: focusModeService)
            }
            // Cold-launch drain: a notification tapped while the app was dead
            // stashes its link before this listener existed.
            if let pending = PendingDeepLink.url {
                PendingDeepLink.url = nil
                deepLinkRouter.handle(pending)
            }
        }
        .onAppear {
            _ = ensureUserExists()
            #if DEBUG
            configureScreenshotModeIfNeeded()
            #endif
        }
        .task {
            let startupUser = ensureUserExists()
            let performedStartup = await startupCoordinator.start(
                storeService: storeService,
                gameCenterService: gameCenterService,
                focusModeService: focusModeService
            )
            guard performedStartup else { return }
            runDeferredStartup(for: startupUser)
        }
    }

    private var mainTabView: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: selectedTabIndex)
                    .tabItem {
                        Label("Home", systemImage: "brain.head.profile")
                    }
                    .tag(MainTab.home)
                    .accessibilityLabel("Home tab")

                TrainingView(
                    externalExercise: $focusUnlockExercise,
                    externalExerciseAutoStart: $focusUnlockExerciseAutoStart
                )
                    .tabItem {
                        Label("Train", systemImage: "dumbbell.fill")
                    }
                    .tag(MainTab.train)
                    .accessibilityLabel("Train tab")

                LeaderboardView()
                    .tabItem {
                        Label("Compete", systemImage: "trophy.fill")
                    }
                    .tag(MainTab.compete)
                    .accessibilityLabel("Compete tab")

                ProgressDashboardView()
                    .tabItem {
                        Label("Insights", systemImage: "chart.bar.xaxis.ascending")
                    }
                    .tag(MainTab.insights)
                    .accessibilityLabel("Insights tab")

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.circle.fill")
                    }
                    .tag(MainTab.profile)
                    .accessibilityLabel("Profile tab")
            }
            .tint(AppColors.accent)
            .symbolRenderingMode(.hierarchical)
            .onChange(of: selectedTab) { _, newTab in
                Analytics.tabViewed(tab: newTab.analyticsName)
            }

            // Achievement toast overlay
            if let firstUnlocked = achievementService.newlyUnlocked.first {
                AchievementToast(achievementType: firstUnlocked) {
                    achievementService.dismissAchievement(firstUnlocked)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }

            // XP toast overlay
            if showingXPToast {
                XPGainedToast(
                    amount: lastXPGained,
                    levelUp: lastLevelUp,
                    newLevel: lastNewLevel
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(99)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showingXPToast = false
                        }
                    }
                }
            }

            // Streak freeze toast overlay
            if showingStreakFreezeToast {
                StreakFreezeToast(message: freezeToastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(98)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation {
                                showingStreakFreezeToast = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $paywallTrigger.shouldShowPaywall) {
            PaywallView(triggerSource: paywallTrigger.triggerContext.rawValue)
        }
        .fullScreenCover(isPresented: $showingStreakCelebration) {
            StreakCelebrationView(streak: celebrationStreak) {
                showingStreakCelebration = false
            }
        }
        .fullScreenCover(isPresented: $showingBrainScoreMilestone) {
            BrainScoreMilestoneView(milestone: milestoneBrainScore) {
                showingBrainScoreMilestone = false
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showingScreenshotBrainAge) {
            ScoreRevealView(
                viewModel: screenshotBrainAgeViewModel(),
                previousScore: brainScoreResults.first,
                userAge: user?.userAge ?? 25,
                onDone: { showingScreenshotBrainAge = false }
            )
        }
        .fullScreenCover(isPresented: $showingScreenshotFocusSetup) {
            FocusModeSetupView(initialStep: 1) {
                showingScreenshotFocusSetup = false
            } onSkip: {
                showingScreenshotFocusSetup = false
            }
        }
        #endif
        .fullScreenCover(isPresented: $showingFocusUnlockSlot) {
            FocusUnlockSlotView(games: TrainingGameCatalog.focusUnlockGames) { game in
                launchFocusUnlockGame(game.type)
            }
            .interactiveDismissDisabled(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .streakMilestoneCelebration)) { notification in
            if let streak = notification.userInfo?["streak"] as? Int {
                celebrationStreak = streak
                withAnimation { showingStreakCelebration = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .brainScoreMilestoneCelebration)) { notification in
            if let milestone = notification.userInfo?["milestone"] as? Int {
                milestoneBrainScore = milestone
                // Delay slightly if streak celebration is showing
                let delay: Double = showingStreakCelebration ? 2.0 : 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation { showingBrainScoreMilestone = true }
                }
            }
        }
        .onChange(of: deepLinkRouter.pendingDestination) { _, destination in
            guard let destination else { return }
            switch destination {
            case .home:
                selectedTab = .home
                deepLinkRouter.pendingDestination = nil
            case .train:
                selectedTab = .train
                deepLinkRouter.pendingDestination = nil
            case .game(_):
                selectedTab = .train
                // Leave pendingDestination so TrainingView can handle it
            case .compete:
                selectedTab = .compete
                deepLinkRouter.pendingDestination = nil
            case .insights:
                selectedTab = .insights
                deepLinkRouter.pendingDestination = nil
            case .profile:
                selectedTab = .profile
                deepLinkRouter.pendingDestination = nil
            case .focusUnlock:
                focusUnlockPending = true
                focusUnlockExpectedExercise = nil
                selectedTab = .train
                Analytics.focusUnlockSlotShown()
                showingFocusUnlockSlot = true
                deepLinkRouter.pendingDestination = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutGameCompleted)) { notification in
            if focusUnlockPending {
                let completedGame = notification.userInfo?["exerciseType"] as? String
                guard FocusUnlockCompletionGate.shouldGrant(
                    completedGameRawValue: completedGame,
                    expectedGame: focusUnlockExpectedExercise
                ) else {
                    focusUnlockPending = false
                    focusUnlockExpectedExercise = nil
                    return
                }

                focusUnlockPending = false
                focusUnlockExpectedExercise = nil
                // Payout is derived from the game that was actually completed —
                // the spin's stake cashes out here.
                let payoutMinutes = ExerciseType(rawValue: completedGame ?? "")
                    .map(FocusUnlockPayout.minutes(for:)) ?? focusModeService.unlockDuration
                lastUnlockMinutes = payoutMinutes
                focusModeService.temporaryUnlock(durationMinutes: payoutMinutes)
                if let gameType = completedGame,
                   let score = notification.userInfo?["score"] as? Double {
                    Analytics.focusUnlockGameCompleted(gameType: gameType, score: Int(score * 100))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showFocusUnlockToast = true
                }
            }
        }
        // Reset the pending flag when the user navigates away from the Train tab
        // without completing. This is a safer trigger than watching
        // focusUnlockExercise — that binding is reset to nil immediately after
        // navigation as part of the standard binding-passthrough pattern, which
        // caused the previous reset logic to fire before the game could even
        // start (the unlock toast then never fired on completion).
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .train && focusUnlockPending {
                focusUnlockPending = false
                focusUnlockExpectedExercise = nil
            }
        }
        .overlay(alignment: .top) {
            if showFocusUnlockToast {
                HStack(spacing: 10) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.mint)
                    Text("Apps unlocked for \(lastUnlockMinutes) min")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppColors.mint.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showFocusUnlockToast = false
                        }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFocusUnlockToast)
            }
        }
    }

    private func launchFocusUnlockGame(_ type: ExerciseType) {
        focusUnlockExpectedExercise = type
        Analytics.focusUnlockGameStarted(gameType: type.rawValue)
        focusUnlockExerciseAutoStart = true
        focusUnlockExercise = type

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            showingFocusUnlockSlot = false
        }
    }

    private func ensureUserExists() -> User {
        if let user { return user }
        let newUser = User()
        modelContext.insert(newUser)
        return newUser
    }

    private func runDeferredStartup(for user: User) {
        let latestBrainAge = brainScoreResults.first?.brainAge
        let totalGames = (try? modelContext.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        Analytics.identify(
            userId: user.id.uuidString,
            isProUser: storeService.isProUser,
            brainAge: latestBrainAge,
            streak: user.currentStreak,
            gamesPlayed: totalGames
        )

        let daysSince = user.lastSessionDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        } ?? -1
        Analytics.appOpened(
            daysSinceLastOpen: daysSince,
            currentStreak: user.currentStreak,
            isProUser: storeService.isProUser
        )

        scheduleStreakRiskIfNeeded(for: user)
        scheduleComebackIfNeeded(for: user)
        if user.notificationsEnabled {
            NotificationService.shared.scheduleWeeklyLeaderboardReset()
        }
        syncWidgetData(for: user)
    }

    private func scheduleStreakRiskIfNeeded(for user: User) {
        guard user.notificationsEnabled, user.currentStreak > 0 else { return }
        let trainedToday = user.lastSessionDate.map { Calendar.current.isDateInToday($0) } ?? false
        if !trainedToday {
            NotificationService.shared.scheduleStreakRisk(streak: user.currentStreak)
        }
    }

    #if DEBUG
    private var screenshotTargetArgument: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screenshot-target") else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }

    private var screenshotOnboardingStartPage: Int? {
        guard ProcessInfo.processInfo.arguments.contains("--screenshot-mode") else { return nil }
        guard let target = screenshotTargetArgument else { return nil }

        switch target {
        case "onboarding-welcome":
            return OnboardingPage.welcome.rawValue
        case "onboarding-attention", "onboarding-attention-result", "onboarding-bridge":
            return OnboardingPage.motivationBridge.rawValue
        case "onboarding-slot", "onboarding-game", "onboarding-game-reward", "onboarding-rank":
            return OnboardingPage.goals.rawValue
        case "onboarding-name":
            return OnboardingPage.name.rawValue
        case "onboarding-goals":
            return OnboardingPage.goals.rawValue
        case "onboarding-age":
            return OnboardingPage.age.rawValue
        case "onboarding-screen-time", "onboarding-screen-time-estimate":
            return OnboardingPage.screenTimeAccess.rawValue
        case "onboarding-lifetime-shock":
            return OnboardingPage.lifetimeShock.rawValue
        case "onboarding-life-receipt",
             "onboarding-life-receipt-years",
             "onboarding-life-receipt-sleep",
             "onboarding-life-receipt-work":
            return OnboardingPage.lifeSquaresReceipt.rawValue
        case "onboarding-life-receipt-phone", "onboarding-life-receipt-rescue":
            return OnboardingPage.lifeSquaresReceipt.rawValue
        case "onboarding-protect-target", "onboarding-willpower-proof":
            return OnboardingPage.protectTarget.rawValue
        case "onboarding-feed-win-moment":
            return OnboardingPage.feedWinMoment.rawValue
        case "onboarding-personalization-beat":
            return OnboardingPage.personalizationBeat.rawValue
        case "onboarding-memo-plan":
            return OnboardingPage.memoPlan.rawValue
        case "onboarding-trial-free":
            return OnboardingPage.trialTrustBridge.rawValue
        case "onboarding-trial-reminder":
            return OnboardingPage.trialReminderBridge.rawValue
        case "onboarding-loader", "onboarding-plan-personalizing":
            return OnboardingPage.planPersonalizing.rawValue
        case "onboarding-focus-mode":
            return OnboardingPage.focusMode.rawValue
        case "onboarding-notification-priming":
            return OnboardingPage.notificationPriming.rawValue
        default:
            return nil
        }
    }

    @MainActor
    private func configureScreenshotModeIfNeeded() {
        guard !didConfigureScreenshotMode else { return }
        guard ProcessInfo.processInfo.arguments.contains("--screenshot-mode") else { return }
        didConfigureScreenshotMode = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let screenshotUser: User
            if let user {
                screenshotUser = user
            } else {
                let newUser = User()
                modelContext.insert(newUser)
                screenshotUser = newUser
            }

            ScreenshotDataGenerator.generate(
                modelContext: modelContext,
                user: screenshotUser,
                gameCenterService: gameCenterService
            )
            storeService.isProUser = true
            focusModeService.isEnabled = true
            focusModeService.dailyAttemptCount = 3
            focusModeService.setUnlockDuration(15)

            switch screenshotTargetArgument {
            case "focus-setup":
                showingScreenshotFocusSetup = true
            case "paywall-hard", "paywall-concise":
                showingScreenshotHardPaywall = true
            case "brain-age":
                showingScreenshotBrainAge = true
            case "train":
                selectedTab = .train
            case "compete":
                selectedTab = .compete
            case "insights":
                selectedTab = .insights
            case "profile":
                selectedTab = .profile
            default:
                selectedTab = .home
            }
        }
    }

    private func screenshotBrainAgeViewModel() -> BrainAssessmentViewModel {
        let viewModel = BrainAssessmentViewModel()
        viewModel.brainScore = 820
        viewModel.brainAge = 25
        viewModel.brainType = .balancedBrain
        viewModel.percentile = 90
        viewModel.digitScore = 85
        viewModel.reactionScore = 78
        viewModel.visualScore = 90
        viewModel.digitMaxCorrect = 9
        viewModel.avgReactionMs = 220
        viewModel.visualMaxCorrect = 7
        return viewModel
    }
    #endif

    private func scheduleComebackIfNeeded(for user: User) {
        guard user.notificationsEnabled else { return }
        guard let lastSession = user.lastSessionDate else { return }
        let daysAgo = Calendar.current.dateComponents([.day], from: lastSession, to: .now).day ?? 0
        if daysAgo >= 2 {
            NotificationService.shared.scheduleComebackNotification(lastTrainedDaysAgo: daysAgo)
        }
    }

    private func syncWidgetData(for user: User) {
        let trainedToday = user.lastSessionDate.map { Calendar.current.isDateInToday($0) } ?? false
        let todaySession = sessions.first { Calendar.current.isDateInToday($0.date) }
        let exercisesToday = todaySession?.exercisesCompleted.count ?? 0

        let latestBrainScore = brainScoreResults.first?.brainScore ?? 0

        WidgetDataService.updateWidgetData(
            streak: user.currentStreak,
            level: user.level,
            levelName: user.levelName,
            xp: user.totalXP,
            xpForNextLevel: user.xpForNextLevel,
            exercisesToday: exercisesToday,
            dailyGoal: user.dailyGoal,
            brainScore: latestBrainScore,
            trainedToday: trainedToday
        )
    }

}

// MARK: - XP Helper

extension ContentView {
    static func awardXP(user: User, score: Double, difficulty: Int, achievementService: AchievementService, modelContext: ModelContext, gameCenterService: GameCenterService? = nil, exerciseType: ExerciseType? = nil, gameScore: Int? = nil) -> (xp: Int, leveledUp: Bool) {
        let xp = user.xpForExercise(score: score, difficulty: difficulty)
        let leveledUp = user.addXP(xp)
        user.totalExercises += 1
        if score >= 0.95 { user.totalPerfectScores += 1 }

        achievementService.checkAchievements(context: modelContext, user: user)

        // Level-ups are celebrated in-app; no redundant push banner.

        // Update widget data centrally after every exercise completion
        let exercisesToday: Int = {
            let startOfDay = Calendar.current.startOfDay(for: Date())
            var descriptor = FetchDescriptor<DailySession>(predicate: #Predicate { $0.date >= startOfDay })
            descriptor.fetchLimit = 1
            let todaySession = (try? modelContext.fetch(descriptor))?.first
            return todaySession?.exercisesCompleted.count ?? 0
        }()

        let latestBrainScore: Int = {
            var descriptor = FetchDescriptor<BrainScoreResult>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first?.brainScore ?? 0
        }()

        // Rolling Brain Score: update domain if game improved it
        if let exerciseType, let rawScore = gameScore,
           let (domain, newDomainScore) = BrainScoring.domainScore(for: exerciseType, gameScore: rawScore, score: score) {

            var bsDescriptor = FetchDescriptor<BrainScoreResult>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            bsDescriptor.fetchLimit = 1
            let latestResult = (try? modelContext.fetch(bsDescriptor))?.first

            let currentMemory = latestResult?.digitSpanScore ?? 0
            let currentSpeed = latestResult?.reactionTimeScore ?? 0
            let currentVisual = latestResult?.visualMemoryScore ?? 0

            var updatedMemory = currentMemory
            var updatedSpeed = currentSpeed
            var updatedVisual = currentVisual

            var improved = false
            switch domain {
            case "memory":
                if newDomainScore > currentMemory {
                    updatedMemory = newDomainScore
                    improved = true
                }
            case "speed":
                if newDomainScore > currentSpeed {
                    updatedSpeed = newDomainScore
                    improved = true
                }
            case "visual":
                if newDomainScore > currentVisual {
                    updatedVisual = newDomainScore
                    improved = true
                }
            default: break
            }

            if improved, latestResult != nil {
                let newBrainScore = BrainScoring.compositeBrainScore(
                    digit: updatedMemory,
                    reaction: updatedSpeed,
                    visual: updatedVisual
                )
                let newAge = BrainScoring.brainAge(from: newBrainScore)

                let result = BrainScoreResult()
                result.date = Date()
                result.brainScore = newBrainScore
                result.brainAge = newAge
                result.digitSpanScore = updatedMemory
                result.reactionTimeScore = updatedSpeed
                result.visualMemoryScore = updatedVisual
                result.digitSpanMax = latestResult?.digitSpanMax ?? 0
                result.reactionTimeAvgMs = latestResult?.reactionTimeAvgMs ?? 0
                result.visualMemoryMax = latestResult?.visualMemoryMax ?? 0
                result.percentile = BrainScoring.percentile(score: newBrainScore)
                result.brainType = BrainScoring.determineBrainType(
                    digit: updatedMemory,
                    reaction: updatedSpeed,
                    visual: updatedVisual
                )
                result.source = .workout

                if domain == "memory", exerciseType == .sequentialMemory {
                    result.digitSpanMax = rawScore
                } else if domain == "speed", exerciseType == .reactionTime {
                    result.reactionTimeAvgMs = rawScore
                } else if domain == "visual", exerciseType == .visualMemory {
                    result.visualMemoryMax = rawScore
                }

                modelContext.insert(result)
                try? modelContext.save()

                let delta = newBrainScore - (latestResult?.brainScore ?? 0)
                if delta > 0 {
                    NotificationCenter.default.post(
                        name: .brainScoreImproved,
                        object: nil,
                        userInfo: ["delta": delta, "newScore": newBrainScore]
                    )
                    NotificationService.shared.scheduleBrainScoreFollowUp(currentScore: newBrainScore)
                    // Report improved brain score to Game Center leaderboard
                    gameCenterService?.reportScore(newBrainScore, leaderboardID: GameCenterService.brainScoreLeaderboard)
                }
            }
        }

        WidgetDataService.updateWidgetData(
            streak: user.currentStreak,
            level: user.level,
            levelName: user.levelName,
            xp: user.totalXP,
            xpForNextLevel: user.xpForNextLevel,
            exercisesToday: exercisesToday,
            dailyGoal: user.dailyGoal,
            brainScore: latestBrainScore,
            trainedToday: true
        )

        // Report to Game Center (reportScore handles auth guard internally)
        if let gc = gameCenterService {
            // Prompt sign-in after first exercise if not authenticated
            if !gc.isAuthenticated, user.totalExercises == 1 {
                gc.authenticate()
            }

            // Always attempt to report — reportScore checks isAuthenticated internally
            gc.reportScore(user.longestStreak, leaderboardID: GameCenterService.longestStreakLeaderboard)
            gc.reportScore(user.totalXP, leaderboardID: GameCenterService.xpLeaderboard)

            // Report individual exercise score to its leaderboard
            if let type = exerciseType, let rawScore = gameScore, rawScore > 0 {
                let leaderboardID: String? = switch type {
                case .reactionTime: GameCenterService.reactionTimeLeaderboard
                case .colorMatch: GameCenterService.colorMatchLeaderboard
                case .speedMatch: GameCenterService.speedMatchLeaderboard
                case .visualMemory: GameCenterService.visualMemoryLeaderboard
                case .sequentialMemory: GameCenterService.numberMemoryLeaderboard
                case .mathSpeed: GameCenterService.mathSpeedLeaderboard
                case .dualNBack: GameCenterService.dualNBackLeaderboard
                case .wordScramble: GameCenterService.wordScrambleLeaderboard
                case .memoryChain: GameCenterService.memoryChainLeaderboard
                case .chimpTest: GameCenterService.chimpTestLeaderboard
                case .verbalMemory: GameCenterService.verbalMemoryLeaderboard
                default: nil
                }
                if let leaderboardID {
                    gc.reportScore(rawScore, leaderboardID: leaderboardID)
                }
            }

            // Sync any newly unlocked achievements
            for achievementType in achievementService.newlyUnlocked {
                gc.reportAchievement(for: achievementType)
            }
        }

        // Track exercise completion
        if let exerciseType {
            Analytics.exerciseCompleted(game: exerciseType.rawValue, score: score, difficulty: difficulty)
        }

        // Record workout game completion if applicable
        if let exerciseType {
            // Post notification so HomeView can check workout completion
            NotificationCenter.default.post(
                name: .workoutGameCompleted,
                object: nil,
                userInfo: ["exerciseType": exerciseType.rawValue, "score": score]
            )
        }

        // Prompt for App Store review at natural moment
        ReviewPromptService.requestIfAppropriate(totalExercises: user.totalExercises, streak: user.currentStreak)

        // Streak milestone celebration
        let milestonesForCelebration = [7, 14, 30, 60, 100]
        if milestonesForCelebration.contains(user.currentStreak) {
            let lastCelebrated = UserDefaults.standard.integer(forKey: "lastCelebratedStreak")
            if lastCelebrated < user.currentStreak {
                UserDefaults.standard.set(user.currentStreak, forKey: "lastCelebratedStreak")
                Analytics.streakMilestone(streak: user.currentStreak)
                NotificationCenter.default.post(
                    name: .streakMilestoneCelebration,
                    object: nil,
                    userInfo: ["streak": user.currentStreak]
                )
            }
        }

        // Brain Score milestone celebration
        let brainScoreMilestones = [500, 600, 700, 800, 900, 1000]
        let latestBrainScoreValue = latestBrainScore
        let highestCelebrated = UserDefaults.standard.integer(forKey: "highestBrainScoreMilestone")
        for milestone in brainScoreMilestones.sorted(by: >) {
            if latestBrainScoreValue >= milestone && highestCelebrated < milestone {
                UserDefaults.standard.set(milestone, forKey: "highestBrainScoreMilestone")
                NotificationCenter.default.post(
                    name: .brainScoreMilestoneCelebration,
                    object: nil,
                    userInfo: ["milestone": milestone]
                )
                break  // Only celebrate highest new milestone
            }
        }

        return (xp, leveledUp)
    }
}
