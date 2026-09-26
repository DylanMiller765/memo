import SwiftUI
import SwiftData

extension Notification.Name {
    static let streakMilestoneCelebration = Notification.Name("streakMilestoneCelebration")
    static let workoutGameCompleted = Notification.Name("workoutGameCompleted")
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
    @State private var showOnboarding = false
    @State private var selectedTab: MainTab = .home
    @State private var storeService = StoreService()
    @State private var paywallTrigger = PaywallTriggerService()
    @State private var trainingManager = TrainingSessionManager()
    @State private var gameCenterService = GameCenterService()
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var focusModeService = FocusModeService()
    @State private var startupCoordinator = StartupCoordinator()
    #if DEBUG
    @State private var didConfigureScreenshotMode = false
    @State private var showingScreenshotFocusSetup = false
    @State private var showingScreenshotHardPaywall = false
    #endif

    @State private var showQuickGame = false
    @State private var focusUnlockExercise: ExerciseType?
    @State private var focusUnlockExerciseAutoStart = false
    @State private var showingFocusUnlockSlot = false

    // Toast state

    // Streak freeze toast state
    @State private var showingStreakFreezeToast = false
    @State private var freezeToastMessage = ""

    // Streak milestone celebration
    @State private var showingStreakCelebration = false
    @State private var celebrationStreak = 0

    // Brain Score milestone celebration

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

    /// Sticker tab icons: full color when selected, grey when not.
    private func stickerTabLabel(_ title: String, _ kind: StickerKind, tab: MainTab) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: StickerIconRenderer.image(kind, size: 26, muted: selectedTab != tab))
                .renderingMode(.original)
        }
    }

    private var mainTabView: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: selectedTabIndex)
                    .tabItem {
                        stickerTabLabel("Home", .house, tab: .home)
                    }
                    .tag(MainTab.home)
                    .accessibilityLabel("Home tab")

                TrainingView(
                    externalExercise: $focusUnlockExercise,
                    externalExerciseAutoStart: $focusUnlockExerciseAutoStart
                )
                    .tabItem {
                        stickerTabLabel("Train", .dumbbell, tab: .train)
                    }
                    .tag(MainTab.train)
                    .accessibilityLabel("Train tab")

                LeaderboardView()
                    .tabItem {
                        stickerTabLabel("Compete", .trophy, tab: .compete)
                    }
                    .tag(MainTab.compete)
                    .accessibilityLabel("Compete tab")

                ProgressDashboardView()
                    .tabItem {
                        stickerTabLabel("Insights", .chart, tab: .insights)
                    }
                    .tag(MainTab.insights)
                    .accessibilityLabel("Insights tab")

                ProfileView()
                    .tabItem {
                        stickerTabLabel("Profile", .person, tab: .profile)
                    }
                    .tag(MainTab.profile)
                    .accessibilityLabel("Profile tab")
            }
            // Selected tab label in mint (matches the sticker world); each tab's own content keeps the app accent below.
            .tint(Color(red: 0.482, green: 0.89, blue: 0.776))
            .symbolRenderingMode(.hierarchical)
            .onChange(of: selectedTab) { _, newTab in
                Analytics.tabViewed(tab: newTab.analyticsName)
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
        #if DEBUG
        .fullScreenCover(isPresented: $showingScreenshotFocusSetup) {
            FocusModeSetupView(initialStep: 1) {
                showingScreenshotFocusSetup = false
            } onSkip: {
                showingScreenshotFocusSetup = false
            }
        }
        #endif
        .fullScreenCover(isPresented: $showingFocusUnlockSlot) {
            FocusUnlockFlowView { showingFocusUnlockSlot = false }
                .interactiveDismissDisabled(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .streakMilestoneCelebration)) { notification in
            if let streak = notification.userInfo?["streak"] as? Int {
                celebrationStreak = streak
                withAnimation { showingStreakCelebration = true }
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
                selectedTab = .train
                Analytics.focusUnlockSlotShown()
                showingFocusUnlockSlot = true
                deepLinkRouter.pendingDestination = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unlockResisted)) { _ in
            ensureUserExists().resistedCount += 1
        }
    }

    private func ensureUserExists() -> User {
        if let user { return user }
        let newUser = User()
        modelContext.insert(newUser)
        return newUser
    }

    private func runDeferredStartup(for user: User) {
        let totalGames = (try? modelContext.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        Analytics.identify(
            userId: user.id.uuidString,
            isProUser: storeService.isProUser,
            brainAge: nil,
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

        WidgetDataService.updateWidgetData(
            streak: user.currentStreak,
            exercisesToday: exercisesToday,
            trainedToday: trainedToday
        )
    }

}


