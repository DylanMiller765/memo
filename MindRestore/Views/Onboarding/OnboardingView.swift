import SwiftUI
import SwiftData
import UIKit
import FamilyControls
import DeviceActivity
import AVKit
import AVFoundation

private extension DeviceActivityReport.Context {
    static let onboardingScreenTimeWeekTotal = Self("Onboarding Screen Time Week Total")
}

enum OnboardingScreenTimeHoursFormatter {
    static func dailyLabel(hours: Double, isEstimate: Bool) -> String {
        guard hours.isFinite, hours > 0 else { return "0h" }
        if hours >= 8 && isEstimate { return "8h+" }

        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 { return "\(wholeHours)h" }
        return "\(wholeHours)h \(minutes)m"
    }
}

enum OnboardingPage: Int, Equatable {
    case welcome = 0
    case name = 1
    case goals = 2
    case age = 3
    case screenTimeAccess = 4
    case lifetimeShock = 5
    case lifeSquaresReceipt = 6
    case protectTarget = 7
    case feedWinMoment = 8
    case personalizationBeat = 9
    case memoPlan = 10
    case trialTrustBridge = 11
    case trialReminderBridge = 12
    case planPersonalizing = 13
    case focusMode = 14
    case notificationPriming = 15
    case targetSelection = 16
    case unlockLoopDemo = 17
    case attentionTime = 18
    case motivationBridge = 19
}

private enum MemoOnboardingVariant: String, CaseIterable {
    case control
    case concise

    static func resolve() -> Self {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--onboarding-variant"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let override = Self(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            return override
        }
        #endif

        return .concise
    }
}

struct OnboardingFlowOrder {
    static let pageCount = 20
    static let monetizationPages: [OnboardingPage] = [
        .trialTrustBridge,
        .planPersonalizing
    ]

    static func page(afterScreenTimeAccess: Bool) -> OnboardingPage {
        .lifetimeShock
    }

    static func page(afterLifetimeShock: Bool) -> OnboardingPage {
        .lifeSquaresReceipt
    }

    static func page(afterLifeSquaresReceipt: Bool) -> OnboardingPage {
        .protectTarget
    }

    static func page(afterProtectTarget: Bool) -> OnboardingPage {
        .feedWinMoment
    }

    static func page(afterFeedWinMoment: Bool) -> OnboardingPage {
        .personalizationBeat
    }

    static func page(afterPersonalizationBeat: Bool) -> OnboardingPage {
        .memoPlan
    }

    static func page(afterMemoPlan: Bool) -> OnboardingPage {
        .trialTrustBridge
    }

    static func page(afterTrialTrustBridge: Bool) -> OnboardingPage {
        .planPersonalizing
    }

    static func page(afterPaywallConverted: Bool) -> OnboardingPage {
        .focusMode
    }
}

struct OnboardingScreenTimeProjectionState: Equatable {
    let isAuthorized: Bool
    let useEstimate: Bool

    var isEstimate: Bool {
        useEstimate
    }

    var receiptSourceLine: String {
        isEstimate ? "Using your estimate" : "Using your Screen Time"
    }

    var canContinueFromScreenTime: Bool {
        isAuthorized || useEstimate
    }
}

struct OnboardingScreenTimeAccessButtonState: Equatable {
    let isRequestingAccess: Bool
    let isAuthorized: Bool
    /// Once the user taps "Don't Allow", iOS never prompts again — asking a
    /// second time silently no-ops. The button has to switch to the only route
    /// that still works, otherwise the page is a dead end.
    var wasDenied: Bool = false

    var title: String {
        if isRequestingAccess {
            return "Checking Screen Time..."
        }
        if isAuthorized {
            return "Show my lifetime cost"
        }
        return wasDenied ? "Open Settings" : "Allow Screen Time"
    }

    var isDisabled: Bool {
        isRequestingAccess
    }

    /// True when tapping should deep-link to Settings rather than re-request.
    var opensSettings: Bool {
        !isAuthorized && wasDenied && !isRequestingAccess
    }
}

struct OnboardingView: View {
    private enum PageNavigationDirection {
        case forward
        case backward
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(FocusModeService.self) private var focusModeService
    @Environment(StoreService.self) private var storeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var users: [User]
    @State private var currentPage = 0
    @State private var onboardingVariant: MemoOnboardingVariant
    @State private var pageNavigationDirection: PageNavigationDirection = .forward
    @State private var selectedGoals: Set<UserFocusGoal> = []
    @State private var selectedGoalOrder: [UserFocusGoal] = []
    @State private var selectedTrapApps: Set<OnboardingTrapApp> = []
    @State private var selectedDistractingAppHours: Double?
    @State private var trialReminderDaysBefore = NotificationService.selectedTrialReminderDaysBefore
    @State private var unlockLoopDemoStartedTracked = false
    @State private var assessmentResult: BrainScoreResult?
    @State private var notificationsEnabled = false
    @State private var enteredName: String = ""
    @State private var selectedAge: Int = 0
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var commitmentCompleted = false
    @State private var onboardingCompletionQueued = false
    @State private var welcomeHeadlineVisible = false
    @State private var welcomeAppsVisible: [Bool] = Array(repeating: false, count: 6)
    @State private var welcomeAppsLeaning = false
    @State private var welcomeAppsPushed: [Bool] = Array(repeating: false, count: 6)
    @State private var welcomeMemoVisible = false
    @State private var welcomeMemoLeaning = false
    @State private var welcomeMemoShoving = false
    @State private var welcomeMemoEnlarged = false
    @State private var welcomeSublineVisible = false
    @State private var welcomeCTAVisible = false
    /// After the bouncer hero animation completes, the bezel demo materializes
    /// in the same screen area. Only flips to true if the demo asset is
    /// bundled — otherwise the bouncer stays as the hero.
    @State private var welcomeBezelVisible = false
    /// Becomes true once the bezel has finished scaling in (or, when the demo
    /// asset is missing, at the equivalent point in time). Gates the "Let's
    /// go" CTA so reflexive tappers can't blow past the entrance before the
    /// bezel has even materialized.
    @State private var welcomeCTATappable = false
    @State private var commitmentBullet1Visible = false
    @State private var commitmentBullet2Visible = false
    @State private var commitmentBullet3Visible = false
    @State private var commitmentBullet4Visible = false
    @State private var nameMascotBob = false
    @State private var nameSubheadVisible = false
    @State private var nameInputVisible = false
    @FocusState private var nameFieldFocused: Bool
    @State private var empathySceneVisible = false
    @State private var empathySignalBroken = false
    @State private var empathyCopyVisible = false
    @State private var empathyCTAVisible = false
    @State private var focusModeWasSetUp = false
    @State private var quickAssessmentBgColor: Color = AppColors.pageBg
    @State private var quickAssessmentIsFullscreen = false
    @State private var screenTimeAuthorized = false
    @State private var isRequestingScreenTimeAccess = false
    @State private var screenTimeEstimateHours: Double = 4
    /// Weekly hours the user dials in to match the rendered Screen Time report.
    /// The report extension is sandboxed and can't pass the real number back,
    /// so the user transcribes it — defaults to 28h (4h/day), below typical
    /// real totals, so most users drag upward to match.
    @State private var reportedWeeklyScreenTimeHours: Double = 28
    @State private var useScreenTimeEstimate = false
    @State private var screenTimeAccessDenied = false
    @State private var showingScreenTimeEstimateSheet = false
    @State private var screenTimeReceiptVisible = false
    @State private var screenTimeReportProbeID = UUID()
    @State private var selectedProtectTarget: PlanBuildBeatContent.ProtectTarget?
    @State private var selectedFeedWinMoment: PlanBuildBeatContent.FeedWinMoment?
    @State private var agePageAppeared = false
    @State private var receiptCount: Int = 0
    /// Single-slot cover state. iOS 17 SwiftUI silently no-ops the second of two
    /// stacked .fullScreenCover(isPresented:) modifiers — using item-based with
    /// an enum forces a clean swap and fixes the "paywall doesn't present" bug.
    @State private var presentedCover: OnboardingCover?
    /// Full-bleed atmosphere behind the memoPlan demo's machine beat — driven
    /// by the page via binding because the page slot can't reach behind the
    /// progress bar.
    @State private var memoPlanAtmosphereVisible = false
    /// "You're in" beat shown right after paywall conversion — hosts the
    /// soft rating pre-prompt.
    @State private var showingPostPurchaseCelebration = false
    /// When non-nil, a building beat overlay is shown over the current page.
    @State private var activeBeat: PlanBuildBeatContent.Beat?
    /// Page to navigate to once the active beat finishes.
    @State private var beatTargetPage: Int?
    @State private var didRouteAfterPaywallConversion = false
    @State private var isCompletingConciseOnboarding = false
    @State private var onboardingStartedAt = Date()
    @State private var currentStepStartedAt = Date()
    @State private var hasTrackedOnboardingStart = false

    enum OnboardingCover: Identifiable {
        case brainAgeReveal
        case paywall
        var id: Self { self }
    }

    var onComplete: () -> Void

    private var routePages: [OnboardingPage] {
        switch onboardingVariant {
        case .control:
            return [
                .welcome, .name, .goals, .age, .screenTimeAccess, .lifetimeShock,
                .lifeSquaresReceipt, .protectTarget, .feedWinMoment, .personalizationBeat,
                .memoPlan, .trialTrustBridge, .planPersonalizing, .focusMode, .notificationPriming
            ]
        case .concise:
            return [
                .welcome, .motivationBridge, .goals,
                .trialTrustBridge, .trialReminderBridge
            ]
        }
    }

    private var totalPages: Int { routePages.count }

    private var currentRouteIndex: Int {
        guard let page = OnboardingPage(rawValue: currentPage),
              let index = routePages.firstIndex(of: page) else { return 0 }
        return index
    }

    private var preConversionPageCount: Int {
        routePages.firstIndex(of: .focusMode) ?? routePages.count
    }

    private var hasScreenTimeInput: Bool {
        useScreenTimeEstimate || hasReached(.lifetimeShock)
    }

    private var annualPlanDisplayPrice: String? {
        storeService.products.first(where: { $0.id == StoreService.annualUltraProductID })?.displayPrice
    }

    init(startPage: Int = 0, previewName: String = "", onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _currentPage = State(initialValue: startPage)
        _onboardingVariant = State(initialValue: MemoOnboardingVariant.resolve())
        _enteredName = State(initialValue: previewName)
        #if DEBUG
        _selectedAge = State(initialValue: Self.screenshotInitialAge())
        _selectedDistractingAppHours = State(initialValue: Self.screenshotInitialDistractingAppHours())
        #endif
    }

    #if DEBUG
    private static func screenshotInitialDistractingAppHours() -> Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode"),
              let index = arguments.firstIndex(of: "--screenshot-target"),
              arguments.indices.contains(index + 1),
              arguments[index + 1] == "onboarding-attention-result" else { return nil }
        return 4
    }

    private static func screenshotInitialAge() -> Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return 0 }
        guard let index = arguments.firstIndex(of: "--screenshot-target") else { return 0 }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return 0 }
        switch arguments[valueIndex] {
        case "onboarding-life-receipt-years",
             "onboarding-life-receipt-sleep",
             "onboarding-life-receipt-work":
            return 20
        default:
            return 0
        }
    }

    private var isScreenTimeEstimateScreenshot: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return false }
        guard let index = arguments.firstIndex(of: "--screenshot-target") else { return false }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return false }
        return arguments[valueIndex] == "onboarding-screen-time-estimate"
    }

    private var isMeasuredLifeReceiptScreenshot: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return false }
        guard let index = arguments.firstIndex(of: "--screenshot-target") else { return false }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return false }
        return [
            "onboarding-lifetime-shock",
            "onboarding-life-receipt",
            "onboarding-life-receipt-years",
            "onboarding-life-receipt-sleep",
            "onboarding-life-receipt-work",
            "onboarding-life-receipt-phone",
            "onboarding-life-receipt-rescue",
            "onboarding-willpower-proof"
        ].contains(arguments[valueIndex])
    }

    private var screenshotLifeReceiptPreviewBeat: OnboardingLifeReceiptBeat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode") else { return nil }
        guard let index = arguments.firstIndex(of: "--screenshot-target") else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        switch arguments[valueIndex] {
        case "onboarding-life-receipt-years":
            return .yearsAhead
        case "onboarding-life-receipt-sleep":
            return .sleepLocked
        case "onboarding-life-receipt-work":
            return .workSchoolLocked
        case "onboarding-life-receipt-rescue":
            return .rescue
        case "onboarding-life-receipt-phone":
            return .phoneTruth
        default:
            return nil
        }
    }
    #endif

    var body: some View {
        ZStack {
            // Onboarding is dark-pinned regardless of system theme — use OB.bg
            // directly so light-mode iPhones don't bleed cream pageBg through
            // the chrome around the TabView. Quick Assessment keeps its
            // dynamic bg color (the assessment animates color shifts).
            OB.bg.ignoresSafeArea()

            // Page-specific atmosphere lifted out of individual pages so
            // blurs/glows extend behind the progress bar instead of clipping
            // at the page's top edge. Pages should leave their atmosphere
            // empty and declare effects here keyed off `currentPage`.
            pageAtmosphere
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: currentPage)

            VStack(spacing: 0) {
                // Progress header is always rendered; visibility controlled by
                // progressHeaderOpacity so it fades on entry/exit of full-bleed
                // editorial pages such as the personalization loader
                // instead of snapping when a conditional flips.
                onboardingProgressHeader
                    .opacity(progressHeaderOpacity)
                    .animation(.easeInOut(duration: 0.30), value: currentPage)
                    .allowsHitTesting(progressHeaderOpacity > 0)

                pageContent
                    .id(currentPage)
                    .transition(onboardingPageTransition)
                    .onChange(of: currentPage) { oldPage, newPage in
                        trackOnboardingStepViewed(from: oldPage, to: newPage)
                        // Animate keyboard dismiss smoothly
                        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        nameFieldFocused = false
                        // Reset commitment typewriter bullets when navigating away
                        commitmentBullet1Visible = false
                        commitmentBullet2Visible = false
                        commitmentBullet3Visible = false
                        commitmentBullet4Visible = false
                    }
            }

            // Transient building-beat overlay, layered above the page content.
            // Driven by `activeBeat`; auto-advances to `beatTargetPage`.
            if let beat = activeBeat {
                OnboardingPlanBuildBeatOverlay(
                    beat: beat,
                    goals: selectedGoals,
                    selectedGoalOrder: selectedGoalsInChoiceOrder,
                    age: selectedAge > 0 ? selectedAge : 25,
                    dailyScreenTimeHours: effectiveDailyScreenTimeHours,
                    isEstimate: projectionIsEstimate,
                    protectTarget: selectedProtectTarget,
                    feedWinMoment: selectedFeedWinMoment,
                    onAdvance: { finishActiveBeat() }
                )
                .transition(.opacity)
                .zIndex(1000)
            }

            if showingPostPurchaseCelebration {
                postPurchaseCelebration
                    .transition(.opacity)
                    .zIndex(1001)
            }

            #if DEBUG
            // Dev-only: jump straight to the paywall to test conversion +
            // everything downstream without walking all 16 screens. Compiled
            // out of release builds.
            if currentPage == 0 && presentedCover == nil &&
                !ProcessInfo.processInfo.arguments.contains("--hide-dev-controls") {
                Button {
                    presentedCover = .paywall
                } label: {
                    Text("DEV → PAYWALL")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 40)
                .zIndex(1002)
            }
            #endif
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .onAppear {
            SoundService.shared.isSuppressed = true
            trackOnboardingStartedIfNeeded()
        }
        .onDisappear {
            SoundService.shared.isSuppressed = false
            if users.first?.hasCompletedOnboarding != true, presentedCover == nil, !onboardingCompletionQueued {
                Analytics.onboardingDroppedOff(
                    lastStep: onboardingStepName(for: currentPage),
                    totalSteps: totalPages,
                    stepIndex: currentRouteIndex,
                    secondsSinceStart: onboardingElapsed,
                    secondsOnStep: currentStepElapsed,
                    goals: onboardingGoalValues,
                    selectedAge: collectedAgeForAnalytics,
                    screenTimeHours: collectedScreenTimeHoursForAnalytics,
                    screenTimeIsEstimate: collectedScreenTimeEstimateFlagForAnalytics,
                    brainAge: assessmentResult?.brainAge,
                    brainScore: assessmentResult?.brainScore,
                    receiptCount: receiptCount,
                    variant: onboardingVariant.rawValue
                )
            }
        }
        // Single-cover slot: brain age reveal first, then paywall after differentiation.
        // Tracked-last-value handles per-cover dismissal routing.
        .fullScreenCover(item: $presentedCover, onDismiss: handleCoverDismiss) { cover in
            switch cover {
            case .brainAgeReveal:
                OnboardingBrainAgeReveal(
                    brainAge: assessmentResult?.brainAge ?? 25,
                    userAge: selectedAge > 0 ? selectedAge : 25,
                    onContinue: { presentedCover = nil }
                )
            case .paywall:
                PaywallView(
                    isHighIntent: true,
                    triggerSource: "onboarding_\(onboardingVariant.rawValue)",
                    isHardPaywall: true,
                    dailyScreenTimeHours: effectiveDailyScreenTimeHours,
                    onboardingAge: hasReached(.age) && selectedAge > 0 ? selectedAge : nil,
                    onboardingGoalSummary: onboardingPlanGoalSummary,
                    screenTimeIsEstimate: hasScreenTimeInput ? projectionIsEstimate : true,
                    hasScreenTimeInput: hasScreenTimeInput,
                    protectTarget: selectedProtectTarget,
                    feedWinMoment: selectedFeedWinMoment,
                    onConversionComplete: routeAfterPaywallConversion
                )
            }
        }
        .onChange(of: presentedCover) { oldValue, newValue in
            // onDismiss fires after the binding is already nil, so capture the
            // outgoing identity here for routing.
            if newValue == nil, oldValue != nil {
                lastDismissedCover = oldValue
            }
        }
    }

    @State private var lastDismissedCover: OnboardingCover?

    private func handleCoverDismiss() {
        // Route based on which cover just closed.
        switch lastDismissedCover {
        case .brainAgeReveal:
            trackOnboardingStepCompleted("revealDismissed")
            goToPage(OnboardingPage.screenTimeAccess.rawValue)
        case .paywall:
            if didRouteAfterPaywallConversion {
                if onboardingVariant == .concise {
                    finishConciseOnboardingAfterConversion()
                }
            } else if storeService.isProUser {
                routeAfterPaywallConversion()
                if onboardingVariant == .concise {
                    finishConciseOnboardingAfterConversion()
                }
            } else {
                trackOnboardingStepCompleted("paywallHardDismissBlocked", extraProperties: [
                    "hard_paywall": true
                ])
                DispatchQueue.main.async {
                    presentedCover = .paywall
                }
            }
        case nil:
            break
        }
        lastDismissedCover = nil
    }

    private func routeAfterPaywallConversion() {
        guard !didRouteAfterPaywallConversion else { return }
        didRouteAfterPaywallConversion = true
        if onboardingVariant == .concise {
            trackOnboardingStepCompleted("paywallConverted", extraProperties: [
                "next_step": "home"
            ])
            return
        }
        trackOnboardingStepCompleted("paywallConverted", extraProperties: [
            "next_step": "focus_mode_setup"
        ])
        goToPage(OnboardingFlowOrder.page(afterPaywallConverted: true).rawValue)
        // Celebration beat over the next page: they just said yes — the
        // single best moment to ask for a rating (soft pre-prompt; only
        // positive responders see the system dialog).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                showingPostPurchaseCelebration = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func finishConciseOnboardingAfterConversion() {
        guard !isCompletingConciseOnboarding else { return }
        isCompletingConciseOnboarding = true

        Task { @MainActor in
            if NotificationService.shared.hasUpcomingTrialReminder {
                notificationsEnabled = await NotificationService.shared.requestPermission()
                if notificationsEnabled {
                    NotificationService.shared.scheduleStoredTrialRemindersIfAuthorized()
                }
            }
            onboardingCompletionQueued = true
            completeOnboarding()
        }
    }

    private var postPurchaseCelebration: some View {
        ZStack {
            OB.bg.opacity(0.97).ignoresSafeArea()

            RadialGradient(
                colors: [OB.success.opacity(0.20), .clear],
                center: .center,
                startRadius: 16,
                endRadius: 320
            )
            .offset(y: -60)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("mascot-celebrate")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .shadow(color: OB.success.opacity(0.30), radius: 26, y: 12)

                Text("You're in.")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .padding(.top, 18)

                Text("Memo is ready when you are.")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .padding(.top, 6)

                Spacer()

                VStack(spacing: 12) {
                    OBContinueButton(title: "Loving it so far") {
                        dismissPostPurchaseCelebration(lovedIt: true)
                    }

                    Button {
                        dismissPostPurchaseCelebration(lovedIt: false)
                    } label: {
                        Text("Not yet — keep going")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OB.fg3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
        }
    }

    private func dismissPostPurchaseCelebration(lovedIt: Bool) {
        trackOnboardingStepCompleted("postPurchaseRatingPrompt", extraProperties: [
            "loved_it": lovedIt
        ])
        if lovedIt {
            ReviewPromptService.requestForNewSubscriber()
        }
        withAnimation(.easeOut(duration: 0.3)) {
            showingPostPurchaseCelebration = false
        }
    }

    private var onboardingElapsed: TimeInterval {
        Date().timeIntervalSince(onboardingStartedAt)
    }

    private var currentStepElapsed: TimeInterval {
        Date().timeIntervalSince(currentStepStartedAt)
    }

    private var onboardingGoalValues: [String] {
        Array(selectedGoals).map(\.rawValue).sorted()
    }

    private var onboardingPlanGoalSummary: String {
        PlanBuildBeatContent.goalSummary(selectedGoals, selectedGoalOrder: selectedGoalsInChoiceOrder)
    }

    private var selectedAgeForAnalytics: Int? {
        selectedAge > 0 ? selectedAge : nil
    }

    private var collectedAgeForAnalytics: Int? {
        hasReached(.age) ? selectedAgeForAnalytics : nil
    }

    private var collectedScreenTimeHoursForAnalytics: Double? {
        guard hasScreenTimeInput else { return nil }
        return effectiveDailyScreenTimeHours
    }

    private var collectedScreenTimeEstimateFlagForAnalytics: Bool? {
        guard collectedScreenTimeHoursForAnalytics != nil else { return nil }
        return projectionIsEstimate
    }

    private func trackOnboardingStartedIfNeeded() {
        guard !hasTrackedOnboardingStart else { return }
        let now = Date()
        onboardingStartedAt = now
        currentStepStartedAt = now
        hasTrackedOnboardingStart = true
        Analytics.onboardingStarted(totalSteps: totalPages, variant: onboardingVariant.rawValue)
        Analytics.onboardingStepViewed(
            step: onboardingStepName(for: currentPage),
            stepIndex: currentRouteIndex,
            totalSteps: totalPages,
            secondsSinceStart: 0,
            variant: onboardingVariant.rawValue
        )
    }

    private func trackOnboardingStepViewed(from oldPage: Int, to newPage: Int) {
        let now = Date()
        Analytics.onboardingStepViewed(
            step: onboardingStepName(for: newPage),
            stepIndex: currentRouteIndex,
            totalSteps: totalPages,
            secondsSinceStart: now.timeIntervalSince(onboardingStartedAt),
            previousStep: onboardingStepName(for: oldPage),
            secondsOnPreviousStep: now.timeIntervalSince(currentStepStartedAt),
            variant: onboardingVariant.rawValue
        )
        currentStepStartedAt = now
    }

    private func onboardingStepName(for page: Int) -> String {
        guard onboardingVariant == .concise else { return Analytics.onboardingStepName(for: page) }
        switch OnboardingPage(rawValue: page) {
        case .welcome: return "story_block"
        case .motivationBridge: return "story_bridge"
        case .goals: return "story_playable_loop"
        case .trialTrustBridge: return "trial_offer"
        case .trialReminderBridge: return "trial_reminder"
        default: return Analytics.onboardingStepName(for: page)
        }
    }

    private func trackOnboardingStepCompleted(_ step: String, extraProperties: [String: Any] = [:]) {
        Analytics.onboardingStep(
            step: step,
            stepIndex: currentRouteIndex,
            totalSteps: totalPages,
            secondsSinceStart: onboardingElapsed,
            secondsOnStep: currentStepElapsed,
            goals: onboardingGoalValues,
            selectedAge: collectedAgeForAnalytics,
            screenTimeHours: collectedScreenTimeHoursForAnalytics,
            screenTimeIsEstimate: collectedScreenTimeEstimateFlagForAnalytics,
            brainAge: assessmentResult?.brainAge,
            brainScore: assessmentResult?.brainScore,
            receiptCount: receiptCount,
            extraProperties: extraProperties,
            variant: onboardingVariant.rawValue
        )
    }

    // MARK: - Page Atmosphere
    //
    // Lives at the outer ZStack level so blur effects extend full-screen
    // (including behind the progress bar). Add new cases as pages adopt
    // atmosphere effects.

    /// Single source of truth for which page to render at a given currentPage.
    /// Wrapped in @ViewBuilder so SwiftUI can apply .id / .transition uniformly
    /// to any active child view.
    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 0: welcomePage
        case 1: namePage
        case 2: goalsPage
        case 3: agePage
        case 4: screenTimeAccessPage
        case 5: lifetimeShockPage
        case 6: lifeSquaresReceiptPage
        case 7: protectTargetPage
        case 8: feedWinMomentPage
        case 9: personalizationBeatPage
        case 10: memoPlanPage
        case 11: trialTrustBridgePage
        case 12: trialReminderPage
        case 13: planPersonalizingPage
        case 14: focusModePage
        case 15: notificationPrimingPage
        case 16: trapSelectionPage
        case 17: unlockLoopDemoPage
        case 18: attentionTimePage
        case 19: motivationBridgePage
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var pageAtmosphere: some View {
        switch currentPage {
        case 0:
            if onboardingVariant == .control { welcomeAtmosphere }
        case OnboardingPage.trialTrustBridge.rawValue:
            if onboardingVariant == .control { trialTrustBridgeAtmosphere }
        case OnboardingPage.planPersonalizing.rawValue:
            // The build-beat gradient must own the whole screen, including
            // the strip behind the progress bar — a black band up top reads
            // as a rendering bug.
            OnboardingPlanBuildBackground()
        case OnboardingPage.memoPlan.rawValue:
            FocusSlotAtmosphere()
                .opacity(memoPlanAtmosphereVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: memoPlanAtmosphereVisible)
        default:
            EmptyView()
        }
    }

    private var trialTrustBridgeAtmosphere: some View {
        ZStack {
            Image("paywall-twilight-hill-bg")
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    OB.bg.opacity(0.10),
                    OB.bg.opacity(0.28),
                    OB.bg.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Progress Header

    /// Pages where the top progress bar is hidden (full-bleed interactive/cinematic moments):
    /// The personalization loader owns its own pacing and hides the header.
    private var progressHeaderOpacity: Double {
        let hiddenPages: Set<Int> = [OnboardingPage.planPersonalizing.rawValue]
        return hiddenPages.contains(currentPage) ? 0 : 1
    }

    /// Single funnel for every page advance / back-step. The animation
    /// context for `currentPage` state changes is tunable here in one place.
    /// The visual transition CURVE itself is defined by `.transition(...)` on
    /// the page container — this `withAnimation` only schedules SwiftUI's
    /// re-render block.
    /// No back arrow once the user has cleared the paywall — pages from
    /// focusMode onward are post-conversion setup, and stepping back would
    /// drop them into the plan-beat / paywall funnel they already passed.
    private var canGoBack: Bool {
        currentRouteIndex > 0 && currentRouteIndex < preConversionPageCount
    }

    private func goToPage(_ page: Int) {
        guard let targetPage = OnboardingPage(rawValue: page),
              let targetIndex = routePages.firstIndex(of: targetPage),
              page != currentPage else { return }
        pageNavigationDirection = targetIndex > currentRouteIndex ? .forward : .backward
        withAnimation(onboardingPageAnimation) {
            currentPage = page
        }
    }

    private func goToNextRoute() {
        let nextIndex = currentRouteIndex + 1
        guard routePages.indices.contains(nextIndex) else { return }
        goToPage(routePages[nextIndex].rawValue)
    }

    private func hasReached(_ page: OnboardingPage) -> Bool {
        guard let index = routePages.firstIndex(of: page) else { return false }
        return currentRouteIndex >= index
    }

    /// Keep the onboarding chrome fixed while the page layer moves as one
    /// continuous deck. A short partial offset reads as a flick on these
    /// visually dense screens; the full-width push preserves spatial context.
    private var onboardingPageTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        let insertionEdge: Edge = pageNavigationDirection == .forward ? .trailing : .leading
        let removalEdge: Edge = pageNavigationDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge),
            removal: .move(edge: removalEdge)
        )
    }

    private var onboardingPageAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.20)
            : .timingCurve(0.65, 0, 0.35, 1, duration: 0.58)
    }

    /// Plays a building beat overlay, then navigates to `target` once it
    /// auto-advances. The beat is transient (overlay, not a page), so back
    /// navigation never replays it.
    private func advance(after beat: PlanBuildBeatContent.Beat, then target: Int) {
        beatTargetPage = target
        let stepName: String
        switch beat {
        case .goals: stepName = "planBeatGoals"
        case .age: stepName = "planBeatAge"
        case .screenTime: stepName = "planBeatScreenTime"
        case .personalization: stepName = "planBeatPersonalization"
        case .final: stepName = "planBeatFinal"
        }
        trackOnboardingStepCompleted(stepName)
        withAnimation(.easeInOut(duration: 0.3)) { activeBeat = beat }
    }

    private func finishActiveBeat() {
        let target = beatTargetPage
        withAnimation(.easeInOut(duration: 0.3)) { activeBeat = nil }
        beatTargetPage = nil
        if let target { goToPage(target) }
    }

    @ViewBuilder
    private var onboardingProgressHeader: some View {
        if onboardingVariant == .concise {
            // Equal-width side slots keep the progress bar on the true
            // center line whether or not the back button is showing.
            HStack(spacing: 0) {
                Button {
                    let previousIndex = currentRouteIndex - 1
                    guard routePages.indices.contains(previousIndex) else { return }
                    goToPage(routePages[previousIndex].rawValue)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OB.fg2)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)
                .accessibilityLabel("Back")
                .accessibilityHidden(!canGoBack)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    ForEach(routePages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentRouteIndex ? OB.accent : Color.white.opacity(0.14))
                            .frame(width: index == currentRouteIndex ? 26 : 16, height: 5)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: currentRouteIndex)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(currentRouteIndex + 1) of \(totalPages)")

                Spacer(minLength: 8)

                Color.clear.frame(width: 44, height: 44)
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
        } else {
        ZStack {
            GeometryReader { proxy in
                let barWidth = min(proxy.size.width * 0.76, 320)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.cardBorder)

                    Capsule()
                        .fill(AppColors.accent)
                        .frame(width: barWidth * onboardingProgress)
                }
                .frame(width: barWidth, height: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 34)

            Button {
                guard canGoBack else { return }
                let previousIndex = currentRouteIndex - 1
                guard routePages.indices.contains(previousIndex) else { return }
                goToPage(routePages[previousIndex].rawValue)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(canGoBack ? AppColors.textSecondary : .clear)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Back")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, currentPage == 4 ? 28 : 10)
        .padding(.bottom, currentPage == 4 ? 0 : 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPage)
        }
    }

    /// Pages 14–15 (focusMode, notificationPriming) are post-conversion setup,
    /// so counting them left the bar at 75% on the last screen before the
    /// paywall — telling the user a quarter remained at the exact moment they
    /// should feel finished. Post-conversion pages run their own 0→100 pass.
    private var onboardingProgress: CGFloat {
        if currentRouteIndex >= preConversionPageCount {
            let postCount = totalPages - preConversionPageCount
            guard postCount > 1 else { return 1 }
            return CGFloat(currentRouteIndex - preConversionPageCount + 1) / CGFloat(postCount)
        }
        guard preConversionPageCount > 1 else { return 1 }
        return CGFloat(currentRouteIndex + 1) / CGFloat(preConversionPageCount)
    }

    private var onboardingGoalOrder: [UserFocusGoal] {
        [.attentionShot, .screenTimeFrying, .doomscrolling, .loseFocus, .forgetInstantly, .getSharper]
    }

    private var selectedGoalsInChoiceOrder: [UserFocusGoal] {
        let tappedGoals = selectedGoalOrder.filter { selectedGoals.contains($0) }
        let untappedOrRestoredGoals = onboardingGoalOrder.filter { goal in
            selectedGoals.contains(goal) && !tappedGoals.contains(goal)
        }
        return tappedGoals + untappedOrRestoredGoals
    }

    private var effectiveDailyScreenTimeHours: Double {
        #if DEBUG
        if isMeasuredLifeReceiptScreenshot { return 50.2 / 7.0 }
        #endif
        if useScreenTimeEstimate { return screenTimeEstimateHours }
        return reportedWeeklyScreenTimeHours / 7.0
    }

    private var projectionIsEstimate: Bool {
        #if DEBUG
        if isMeasuredLifeReceiptScreenshot { return false }
        #endif
        return screenTimeProjectionState.isEstimate
    }

    private var screenTimeProjectionState: OnboardingScreenTimeProjectionState {
        OnboardingScreenTimeProjectionState(
            isAuthorized: screenTimeAuthorized,
            useEstimate: useScreenTimeEstimate
        )
    }

    private var screenTimeAccessButtonState: OnboardingScreenTimeAccessButtonState {
        OnboardingScreenTimeAccessButtonState(
            isRequestingAccess: isRequestingScreenTimeAccess,
            isAuthorized: screenTimeAuthorized,
            wasDenied: screenTimeAccessDenied
        )
    }

    private var screenTimeAccessButtonTitle: String { screenTimeAccessButtonState.title }

    private var screenTimeAccessButtonDisabled: Bool {
        screenTimeAccessButtonState.isDisabled
    }

    private var screenTimeAccessSubtitle: String {
        if screenTimeAccessDenied {
            // Says what to actually do — iOS won't ask twice, so "can't do the
            // math without it" left people staring at a button that no-ops.
            return "iOS only asks once. Turn Screen Time on in Settings → Screen Time, or enter your hours by hand."
        }
        return "Memo needs Screen Time to do the scary math. It never leaves your phone."
    }

    private var yearsUntilEighty: Int {
        max(1, 80 - (selectedAge > 0 ? selectedAge : 25))
    }

    private var projectedScreenTimeHours: Int {
        Int((effectiveDailyScreenTimeHours * 365 * Double(yearsUntilEighty)).rounded())
    }

    private var yesterdayScreenTimeFilter: DeviceActivityFilter {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: yesterdayStart, end: todayStart)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private func reloadScreenTimeReportProbe() {
        screenTimeReportProbeID = UUID()
    }

    private func formatProjectedHours(_ value: Int) -> String {
        if value >= 1000 {
            let rounded = Int((Double(value) / 1000.0).rounded()) * 1000
            return rounded.formatted()
        }
        return value.formatted()
    }

    private var projectedYearsText: String {
        String(format: "%.1f", Double(projectedScreenTimeHours) / 8760.0)
    }

    // MARK: - Personal Scare (287×) Page
    //
    // Sits AFTER ScreenTime auth, BEFORE assessment. Shows the user's real pickup
    // count from yesterday — concrete personal stat that lands harder than any
    // industry average. Auth was already negotiated on screenTimeAccessPage so
    // we don't re-prompt here.

    private var personalScarePage: some View {
        FocusOnboardPersonalUnlocks(
            onContinue: {
                trackOnboardingStepCompleted("personalScare")
                goToPage(6) // → focusMode
            },
            authorized: screenTimeAuthorized,
            count: 287,
            previouslyDenied: (focusModeService.authorizationStatus == .denied)
        )
        .onAppear {
            screenTimeAuthorized = (focusModeService.authorizationStatus == .approved)
        }
    }

    @ViewBuilder
    private var welcomePage: some View {
        if onboardingVariant == .concise {
            conciseWelcomePage
        } else {
            legacyWelcomePage
        }
    }

    private var conciseWelcomePage: some View {
        OnboardingIntroPage(isActive: currentPage == OnboardingPage.welcome.rawValue) {
            trackOnboardingStepCompleted("story_block", extraProperties: ["product_demo": true])
            goToNextRoute()
        }
    }

    private var legacyWelcomePage: some View {
        ZStack {
            // Atmosphere is rendered at the outer body so it can extend behind
            // the progress bar. The page body itself sits on the global pageBg.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    OBEyebrow(text: "MEMO · APP BLOCKER + BRAIN TRAINER")
                    // Headline morphs once the bezel materializes — shorter copy
                    // gives the phone-in-phone room to breathe without stealing
                    // the brand line entirely.
                    ZStack(alignment: .topLeading) {
                        (Text("The only app blocker\n") + Text("that trains ur brain.").foregroundColor(OB.accent))
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(OB.fg)
                            .lineSpacing(1)
                            .kerning(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(welcomeBezelVisible ? 0 : 1)

                        Text("Block apps.\nTrain to unlock.")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(OB.fg)
                            .kerning(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(welcomeBezelVisible ? 1 : 0)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .opacity(welcomeHeadlineVisible ? 1 : 0)
                .offset(y: welcomeHeadlineVisible ? 0 : 8)

                Spacer(minLength: 28)

                ZStack {
                    WelcomeBouncerHero(
                        appsVisible: welcomeAppsVisible,
                        appsLeaning: welcomeAppsLeaning,
                        appsPushed: welcomeAppsPushed,
                        memoVisible: welcomeMemoVisible,
                        memoLeaning: welcomeMemoLeaning,
                        memoShoving: welcomeMemoShoving,
                        memoEnlarged: welcomeMemoEnlarged
                    )
                    .opacity(welcomeBezelVisible ? 0 : 1)

                    WelcomeDemoBezel(isActive: welcomeBezelVisible && currentPage == 0)
                        .opacity(welcomeBezelVisible ? 1 : 0)
                        .scaleEffect(welcomeBezelVisible ? 1.0 : 0.92)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .offset(y: welcomeBezelVisible ? -24 : 0)
                .animation(.easeOut(duration: 0.34), value: welcomeBezelVisible)

                Spacer(minLength: 28)

                Text("Every unlock starts with one quick brain rep.")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
                    .opacity(welcomeSublineVisible ? 1 : 0)
                    .offset(y: welcomeSublineVisible ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                OBContinueButton(title: "Show me how") {
                    trackOnboardingStepCompleted("welcome")
                    goToNextRoute()
                }
                // Disable taps until the bezel has finished materializing.
                // Otherwise the button is hit-testable behind its .opacity(0)
                // fade-in and a fast user can blow past the bouncer + bezel
                // entrance without seeing them.
                .disabled(!welcomeCTATappable)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .heavy))
                    Text("No ads. No data sold. Just your brain fighting back.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(OB.fg3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .opacity(welcomeCTAVisible ? 1 : 0)
            .offset(y: welcomeCTAVisible ? 0 : 8)
            .allowsHitTesting(welcomeCTATappable)
        }
        .preferredColorScheme(.dark)
        .onAppear { startWelcomeEntrance() }
    }

    private var welcomeAtmosphere: some View {
        // Two blurs that extend behind the progress bar (rendered at the
        // outer ZStack level, ignoring safe area). Top-left accent blur
        // bleeds through the bar area, creating a continuous "you vs them"
        // color tension; bottom-right coral anchors the app pile side.
        ZStack {
            Circle()
                .fill(OB.accent.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 76)
                .offset(x: -130, y: -180)

            Circle()
                .fill(OB.coral.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 68)
                .offset(x: 140, y: 200)
        }
    }

    private func startWelcomeEntrance() {
        let hasDemoAsset = Bundle.main.url(forResource: "onboarding_demo", withExtension: "mp4") != nil
        // The CTA appears early and is tappable the moment it's visible.
        // Fast tappers are the highest-intent users — the demo keeps playing
        // for everyone who wants to watch, but nobody waits on a dead button.
        let ctaRevealDelay: TimeInterval = hasDemoAsset ? 1.40 : 1.05
        let ctaTapDelay: TimeInterval = ctaRevealDelay

        // Reset state so re-entering the welcome (e.g., from a back swipe) replays.
        welcomeHeadlineVisible = false
        welcomeAppsVisible = Array(repeating: false, count: 6)
        welcomeAppsLeaning = false
        welcomeAppsPushed = Array(repeating: false, count: 6)
        welcomeMemoVisible = false
        welcomeMemoLeaning = false
        welcomeMemoShoving = false
        welcomeMemoEnlarged = false
        welcomeSublineVisible = false
        welcomeCTAVisible = false
        welcomeCTATappable = false
        welcomeBezelVisible = false

        // Beat 1 — Headline (threat is being framed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.4)) { welcomeHeadlineVisible = true }
        }

        // Beat 2 — Apps press in (cascade from right, 0.40s start, 0.08s stagger)
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40 + Double(i) * 0.08) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    if i < welcomeAppsVisible.count {
                        welcomeAppsVisible[i] = true
                    }
                }
            }
        }

        // Beat 3 — Memo arrives, holds the line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78)) {
                welcomeMemoVisible = true
            }
        }

        // Beat 4 — TENSION: apps lean toward Memo, Memo leans into them
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.40) {
            withAnimation(.easeOut(duration: 0.30)) {
                welcomeAppsLeaning = true
                welcomeMemoLeaning = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // Beat 5 — THE SHOVE: Memo bursts forward, apps fly off-screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.80) {
            withAnimation(.easeOut(duration: 0.20)) {
                welcomeAppsLeaning = false
                welcomeMemoLeaning = false
            }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.70)) {
                welcomeMemoShoving = true
            }
        }
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.80 + Double(i) * 0.04) {
                withAnimation(.easeIn(duration: 0.5)) {
                    if i < welcomeAppsPushed.count {
                        welcomeAppsPushed[i] = true
                    }
                }
            }
        }

        // Beat 6 — Snapback: Memo recovers from the shove with overshoot
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.10) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.55)) {
                welcomeMemoShoving = false
            }
        }

        // Beat 7 — VICTORY: Memo enlarges
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35) {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.62)) {
                welcomeMemoEnlarged = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // Beat 8 — Copy + CTA settle in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.35)) { welcomeSublineVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ctaRevealDelay) {
            withAnimation(.easeOut(duration: 0.4)) { welcomeCTAVisible = true }
        }

        // Beat 9 — Metaphor → receipts. The bouncer hero hands off to the
        // phone-in-phone bezel demo. Only fires if the asset is bundled, so
        // shipping without onboarding_demo.mp4 cleanly falls back to the
        // existing welcome experience.
        if hasDemoAsset {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.30) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    welcomeBezelVisible = true
                }
            }
        }

        // Beat 10 — Unlock the CTA. With the bundled demo, hold this until the
        // phone-in-phone has played for a few seconds; otherwise fast tappers
        // can skip before they understand the block → train → unlock loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + ctaTapDelay) {
            welcomeCTATappable = true
        }
    }

    // MARK: - Name Entry Page

    // MARK: - Name Entry Page (redesigned)
    //
    // Memo introduces himself in first person; the user types their name on a
    // borderless underlined input field. No big Continue button — return submits.
    // Skip is a tiny tertiary link. Page is the user's first interactive moment,
    // designed to feel personal, not like a form. Pinned to dark mode + FO
    // design tokens for visual continuity with Industry Scare.
    private var namePage: some View {
        // Local color tokens — match FO.bg / FO.accent from FocusOnboardingPages.swift
        let pageBg = Color(red: 0.039, green: 0.039, blue: 0.059)
        let accent = Color(red: 0.408, green: 0.565, blue: 0.996)
        let textPrimary = Color.white.opacity(0.94)
        let textSecondary = Color.white.opacity(0.62)
        let textTertiary = Color.white.opacity(0.40)

        return ZStack {
            pageBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 18)

                // Memo waving in top-left, gentle bob
                Image("mascot-welcome")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .offset(y: nameMascotBob ? -4 : 4)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: nameMascotBob)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                // Memo's intro — typewriter on the headline, fade-up on the question
                VStack(alignment: .leading, spacing: 6) {
                    TypewriterText(fullText: "Hi, I'm Memo.")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)

                    Text("What should I call you?")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .opacity(nameSubheadVisible ? 1 : 0)
                        .offset(y: nameSubheadVisible ? 0 : 6)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                // Subtle label, no military cosplay
                Text("YOUR NAME")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .opacity(nameInputVisible ? 1 : 0)

                // Borderless underlined input — feels like signing on a line.
                // Whole row is one tap target so taps anywhere along the bar
                // focus the field, not just the narrow text content area.
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $enteredName)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(textPrimary)
                    .tint(accent)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { dismissAndAdvance() }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Underline shifts color on focus
                    Rectangle()
                        .fill(nameFieldFocused ? accent : Color.white.opacity(0.35))
                        .frame(height: 1.5)
                        .animation(.easeInOut(duration: 0.25), value: nameFieldFocused)
                }
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
                .onTapGesture { nameFieldFocused = true }
                .opacity(nameInputVisible ? 1 : 0)

                Spacer()

                // Subtle skip link, not a button
                HStack {
                    Spacer()
                    Button {
                        enteredName = ""
                        dismissAndAdvance()
                    } label: {
                        Text("Skip name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(textTertiary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar {
            // Keyboard accessory — quiet "Done" path for users who don't tap return
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    dismissAndAdvance()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                }
            }
        }
        .onAppear {
            nameMascotBob = true
            nameSubheadVisible = false
            nameInputVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.4)) { nameSubheadVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) { nameInputVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if currentPage == 1 { nameFieldFocused = true }
            }
        }
        .onDisappear {
            nameFieldFocused = false
        }
    }

    private func dismissAndAdvance() {
        nameFieldFocused = false
        trackOnboardingStepCompleted("name", extraProperties: [
            "provided_name": !enteredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ])
        goToPage(2)
    }

    @ViewBuilder
    private var goalsPage: some View {
        if onboardingVariant == .concise {
            OnboardingPlayableLoopPage(previewStage: screenshotTryItStage) { levelsCleared in
                trackOnboardingStepCompleted("story_playable_loop", extraProperties: [
                    "demo_game": "visual_memory",
                    "used_product_slot": true,
                    "used_product_game": true,
                    "preview_levels_cleared": levelsCleared,
                    "preview_only": true
                ])
                goToNextRoute()
            }
        } else {
            legacyGoalsPage
        }
    }

    private var legacyGoalsPage: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 900
            let headerHeight: CGFloat = isCompact ? 74 : 104

            ZStack(alignment: .topTrailing) {
                FeedHeistBackdrop(isCompact: isCompact)
                    .padding(.top, isCompact ? 12 : 18)
                    .padding(.trailing, isCompact ? -8 : 0)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: isCompact ? 0 : 2)

                    MemoLookoutHeader(isCompact: isCompact, height: headerHeight)
                        .padding(.horizontal, 24)
                        .padding(.bottom, isCompact ? 0 : 8)

                    VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                        Text("What do you\nwant back?")
                            .font(.system(size: isCompact ? 28 : 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(isCompact ? -2 : 1)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Pick up to 3. Memo builds your block plan around this.")
                            .font(.system(size: isCompact ? 13 : 16, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, isCompact ? 5 : 14)

                    // Scrolls so the sixth goal isn't buried under the pinned
                    // CTA on short screens — SE users could only reach five.
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Divider()
                                .overlay(AppColors.cardBorder)

                            ForEach(Array(onboardingGoalOrder.enumerated()), id: \.element.id) { index, goal in
                                GoalCard(goal: goal, index: index, isSelected: selectedGoals.contains(goal), isCompact: isCompact) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                        if selectedGoals.contains(goal) {
                                            selectedGoals.remove(goal)
                                            selectedGoalOrder.removeAll { $0 == goal }
                                        } else if selectedGoals.count < 3 {
                                            selectedGoals.insert(goal)
                                            selectedGoalOrder.append(goal)
                                        }
                                    }
                                }

                                Divider()
                                    .overlay(AppColors.cardBorder.opacity(selectedGoals.contains(goal) ? 0.9 : 0.7))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    Spacer(minLength: isCompact ? 2 : 12)
                }
                .responsiveContent(maxWidth: 500)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            onboardingBottomBar {
                continueButton("Lock it in") {
                    trackOnboardingStepCompleted("goals")
                    advance(after: .goals, then: 3) // play beat, then → age
                }
                .disabled(selectedGoals.isEmpty)
                .opacity(selectedGoals.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { nameFieldFocused = false }
    }

    private var trapSelectionPage: some View {
        OnboardingVisualMemoryPage(previewCompleted: screenshotGameReward) { completed in
            trackOnboardingStepCompleted("story_play", extraProperties: [
                "demo_game": "visual_memory",
                "used_product_game": true,
                "preview_round_completed": completed,
                "leaderboard_teaser_viewed": completed
            ])
            goToNextRoute()
        }
    }

    /// Screenshot-mode entry point into the Try it page's later beats.
    private var screenshotTryItStage: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode"),
              let index = arguments.firstIndex(of: "--screenshot-target"),
              arguments.indices.contains(index + 1) else { return nil }
        switch arguments[index + 1] {
        case "onboarding-game-reward": return 2
        case "onboarding-rank": return 3
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private var screenshotGameReward: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-mode"),
              let index = arguments.firstIndex(of: "--screenshot-target"),
              arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "onboarding-game-reward"
        #else
        return false
        #endif
    }

    private var attentionTimePage: some View {
        OnboardingAttentionTimePage(selectedHours: $selectedDistractingAppHours) {
            var properties: [String: Any] = [
                "estimate_skipped": selectedDistractingAppHours == nil
            ]
            if let hours = selectedDistractingAppHours {
                properties["estimated_distracting_app_hours_daily"] = hours
                properties["estimated_distracting_app_days_annual"] = Int((hours * 365 / 24).rounded())
            }
            trackOnboardingStepCompleted("story_attention_time", extraProperties: properties)
            goToNextRoute()
        }
    }

    private var motivationBridgePage: some View {
        OnboardingMotivationBridgePage {
            trackOnboardingStepCompleted("story_bridge")
            goToNextRoute()
        }
    }

    private var unlockLoopDemoPage: some View {
        OnboardingUnlockedFocusPage {
            trackOnboardingStepCompleted("story_unlock", extraProperties: [
                "product_focus_card": true,
                "preview_only": true
            ])
            goToNextRoute()
        }
    }

    private var trialReminderPage: some View {
        OnboardingTrialReminderView(
            trialLabel: storeService.annualFreeTrialLabel,
            trialDays: storeService.annualFreeTrialDays,
            selectedDaysBefore: $trialReminderDaysBefore,
            onContinue: {
            NotificationService.shared.setTrialReminderDaysBefore(trialReminderDaysBefore)
            trackOnboardingStepCompleted("trialReminderBridge", extraProperties: [
                "reminder_requires_notification_permission": true,
                "reminder_days_before_trial_end": trialReminderDaysBefore
            ])
            presentedCover = .paywall
        })
        .task {
            // Reminder dates come from the StoreKit trial length; make sure the
            // offer is loaded even if this page is reached first.
            if storeService.products.isEmpty {
                await storeService.loadProducts()
            }
        }
    }

    private var lifetimeShockPage: some View {
        OnboardingLifetimeShockView(
            age: selectedAge > 0 ? selectedAge : 25,
            dailyScreenTimeHours: effectiveDailyScreenTimeHours,
            isEstimate: projectionIsEstimate,
            isLoadingScreenTime: false,
            onContinue: {
                let projection = OnboardingLifetimeProjection(
                    age: selectedAge > 0 ? selectedAge : 25,
                    dailyScreenTimeHours: effectiveDailyScreenTimeHours
                )
                trackOnboardingStepCompleted("lifetimeShock", extraProperties: [
                    "daily_screen_time_hours": effectiveDailyScreenTimeHours,
                    "screen_time_is_estimate": projectionIsEstimate,
                    "screen_time_source": useScreenTimeEstimate ? "estimate" : "user_reported_weekly",
                    "phone_years": projection.phoneYears,
                    "phone_years_text": projection.phoneYearsText
                ])
                goToPage(OnboardingFlowOrder.page(afterLifetimeShock: true).rawValue)
            }
        )
    }

    private var lifeSquaresReceiptPage: some View {
        OnboardingLifeSquaresReceiptView(
            age: selectedAge > 0 ? selectedAge : 25,
            dailyScreenTimeHours: effectiveDailyScreenTimeHours,
            isEstimate: projectionIsEstimate,
            isLoadingScreenTime: false,
            sourceLine: screenTimeProjectionState.receiptSourceLine,
            previewBeat: {
                #if DEBUG
                return screenshotLifeReceiptPreviewBeat
                #else
                return nil
                #endif
            }(),
            onContinue: {
                trackOnboardingStepCompleted("lifeSquaresReceipt", extraProperties: [
                    "daily_screen_time_hours": effectiveDailyScreenTimeHours,
                    "screen_time_is_estimate": projectionIsEstimate,
                    "screen_time_source": useScreenTimeEstimate ? "estimate" : "user_reported_weekly",
                    "projected_screen_time_hours": projectedScreenTimeHours
                ])
                goToPage(OnboardingFlowOrder.page(afterLifeSquaresReceipt: true).rawValue)
            }
        )
    }

    private var protectTargetPage: some View {
        OnboardingPersonalizationQuestionView(
            title: "What are you protecting?",
            subtitle: "Pick what the feed keeps stealing from.",
            options: PlanBuildBeatContent.ProtectTarget.allCases,
            selectedOption: selectedProtectTarget,
            emoji: { $0.emoji },
            label: { $0.title },
            onSelect: { selectedProtectTarget = $0 },
            onContinue: {
                guard let selectedProtectTarget else { return }
                trackOnboardingStepCompleted("protectTarget", extraProperties: [
                    "protect_target": selectedProtectTarget.rawValue
                ])
                goToPage(OnboardingFlowOrder.page(afterProtectTarget: true).rawValue)
            }
        )
    }

    private var feedWinMomentPage: some View {
        OnboardingPersonalizationQuestionView(
            title: "When does the feed usually win?",
            subtitle: "Memo uses this to shape your first guardrail.",
            options: PlanBuildBeatContent.FeedWinMoment.allCases,
            selectedOption: selectedFeedWinMoment,
            emoji: { $0.emoji },
            label: { $0.title },
            onSelect: { selectedFeedWinMoment = $0 },
            onContinue: {
                guard let selectedFeedWinMoment else { return }
                trackOnboardingStepCompleted("feedWinMoment", extraProperties: [
                    "feed_win_moment": selectedFeedWinMoment.rawValue
                ])
                goToPage(OnboardingFlowOrder.page(afterFeedWinMoment: true).rawValue)
            }
        )
    }

    private var personalizationBeatPage: some View {
        OB.bg
            .ignoresSafeArea()
            .onAppear {
                guard activeBeat == nil else { return }
                advance(
                    after: .personalization,
                    then: OnboardingFlowOrder.page(afterPersonalizationBeat: true).rawValue
                )
            }
    }

    private var willpowerProofPage: some View {
        OnboardingWillpowerProofView {
            trackOnboardingStepCompleted("willpowerProof", extraProperties: [
                "next_step": "memo_plan"
            ])
            goToPage(OnboardingFlowOrder.page(afterPersonalizationBeat: true).rawValue)
        }
    }

    private var memoPlanPage: some View {
        OnboardingMemoPlanView(
            selectedGoals: selectedGoals,
            selectedGoalOrder: selectedGoalsInChoiceOrder,
            atmosphereVisible: $memoPlanAtmosphereVisible,
            onContinue: {
                trackOnboardingStepCompleted("memoPlan")
                goToPage(OnboardingFlowOrder.page(afterMemoPlan: true).rawValue)
            }
        )
    }

    private var planPersonalizingPage: some View {
        OnboardingPlanFinalBeatView(
            goals: selectedGoals,
            selectedGoalOrder: selectedGoalsInChoiceOrder,
            age: selectedAge > 0 ? selectedAge : 25,
            dailyScreenTimeHours: effectiveDailyScreenTimeHours,
            isEstimate: projectionIsEstimate,
            protectTarget: selectedProtectTarget,
            feedWinMoment: selectedFeedWinMoment,
            onComplete: {
                trackOnboardingStepCompleted("planBeatFinal", extraProperties: [
                    "personalization_progress_completed": 100,
                    "next_step": "paywall"
                ])
                presentedCover = .paywall
            }
        )
    }

    private var trialTrustBridgePage: some View {
        OnboardingTrialOfferView(
            hasTrial: storeService.annualFreeTrialLabel != nil,
            isLoadingOffer: storeService.isLoading ||
                (storeService.products.isEmpty && storeService.purchaseError == nil),
            loadFailed: !storeService.isLoading &&
                storeService.products.isEmpty && storeService.purchaseError != nil,
            onRetry: {
                storeService.purchaseError = nil
                Task { await storeService.loadProducts() }
            },
            onContinue: {
                let hasTrial = storeService.annualFreeTrialLabel != nil
                trackOnboardingStepCompleted("trialTrustBridge", extraProperties: [
                    "next_step": onboardingVariant == .control
                        ? "plan_personalizing"
                        : (hasTrial ? "trial_reminder" : "paywall"),
                    "trial_eligible": hasTrial,
                    "annual_price_loaded": annualPlanDisplayPrice != nil
                ])
                if onboardingVariant == .concise {
                    if hasTrial {
                        goToNextRoute()
                    } else {
                        presentedCover = .paywall
                    }
                } else {
                    goToPage(OnboardingFlowOrder.page(afterTrialTrustBridge: true).rawValue)
                }
            }
        )
        .task {
            if storeService.products.isEmpty {
                await storeService.loadProducts()
            }
        }
    }

    // MARK: - Screen Time Access Page

    private var screenTimeAccessContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: screenTimeAuthorized ? 18 : 24)

            if screenTimeAuthorized {
                // Receipt-style header: the Apple-rendered weekly total below is
                // the headline, so the top stays a single quiet eyebrow. The
                // report already says "hours on your phone this week" — no
                // caption needed.
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Screen Time connected")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
                .foregroundStyle(OB.accent)
                .padding(.horizontal, 28)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("See what\nyour phone takes.")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(screenTimeAccessSubtitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
            }

            if screenTimeAuthorized {
                screenTimePatternReport
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                screenTimePermissionPrimer
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 8)
        }
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    private var screenTimeAccessPage: some View {
        ScrollView(showsIndicators: false) {
            screenTimeAccessContent
        }
        .scrollBounceBehavior(.basedOnSize)
        // Pinned outside the scroll region: on iPhone SE the button was sliced
        // by the bottom edge and the reassurance line was off-screen entirely.
        // Everything downstream depends on this grant.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            onboardingBottomBar {
                VStack(spacing: 12) {
                    if screenTimeAuthorized {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Stays on your phone")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .tracking(0.9)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(OB.fg3)
                        .opacity(screenTimeReceiptVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.26), value: screenTimeReceiptVisible)
                    }

                    continueButton(screenTimeAccessButtonTitle) {
                        if screenTimeAuthorized {
                            useScreenTimeEstimate = false
                            trackOnboardingStepCompleted("screenTimeAccess", extraProperties: [
                                "screen_time_permission": "approved_existing",
                                "reported_weekly_screen_time_hours": reportedWeeklyScreenTimeHours
                            ])
                            goToPage(OnboardingFlowOrder.page(afterScreenTimeAccess: true).rawValue)
                        } else if screenTimeAccessButtonState.opensSettings {
                            openSystemSettings()
                        } else {
                            requestScreenTimeForOnboarding()
                        }
                    }
                    .disabled(screenTimeAccessButtonDisabled)
                    .opacity(screenTimeAccessButtonDisabled ? 0.6 : 1)

                    if screenTimeAccessDenied {
                        // The only way off this page before this existed was to
                        // delete the app. The estimate still drives the receipt;
                        // real authorization is negotiated again at focus setup.
                        Button {
                            trackOnboardingStepCompleted("screenTimeEstimateOpened", extraProperties: [
                                "screen_time_permission": "denied"
                            ])
                            showingScreenTimeEstimateSheet = true
                        } label: {
                            Text("Enter my hours by hand")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.accent)
                                .underline()
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    } else if !screenTimeAuthorized {
                        Text("Required. The math doesn't work without it.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            if isScreenTimeEstimateScreenshot {
                screenTimeAuthorized = false
                useScreenTimeEstimate = false
                screenTimeReceiptVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showingScreenTimeEstimateSheet = true
                }
                return
            }
            #endif
            syncScreenTimeAccessOnAppear()
        }
        // Returning from Settings doesn't re-fire onAppear, so without this the
        // page would still show the denied state after they'd just granted it.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            guard currentPage == OnboardingPage.screenTimeAccess.rawValue else { return }
            syncScreenTimeAccessOnAppear()
        }
        .onDisappear {
            screenTimeReceiptVisible = false
        }
        .sheet(isPresented: $showingScreenTimeEstimateSheet) {
            ScreenTimeEstimateSheet(
                selection: $screenTimeEstimateHours,
                onConfirm: {
                    useScreenTimeEstimate = true
                    showingScreenTimeEstimateSheet = false
                    trackOnboardingStepCompleted("screenTimeAccess", extraProperties: [
                        "screen_time_permission": "estimate",
                        "screen_time_estimate_hours": screenTimeEstimateHours
                    ])
                    goToPage(OnboardingFlowOrder.page(afterScreenTimeAccess: true).rawValue)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var dailyScreenTimeLabel: String {
        OnboardingScreenTimeHoursFormatter.dailyLabel(
            hours: effectiveDailyScreenTimeHours,
            isEstimate: projectionIsEstimate
        )
    }

    private var screenTimeHoursNumber: String {
        if effectiveDailyScreenTimeHours >= 8 && projectionIsEstimate {
            return "8+"
        }
        return String(format: "%.1f", effectiveDailyScreenTimeHours)
    }

    private var screenTimeDayUsedFraction: CGFloat {
        CGFloat(min(max(effectiveDailyScreenTimeHours / 24, 0.035), 1))
    }

    private var screenTimeRemainingLabel: String {
        let remaining = max(0, 24 - effectiveDailyScreenTimeHours)
        return String(format: "%.1fh left", remaining)
    }

    private var yesterdayDeviceActivityFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: yesterdayStart, end: todayStart)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private var weeklyScreenTimeDeviceActivityFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: weekStart, end: todayStart)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private var screenTimePatternReport: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceActivityReport(.onboardingScreenTimeWeekTotal, filter: weeklyScreenTimeDeviceActivityFilter)
                .frame(height: 184)
                .id(screenTimeReportProbeID)

            weeklyMatchSection
                .padding(.top, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var weeklyDailyEquivalentLabel: String {
        String(format: "≈ %.1fh a day", reportedWeeklyScreenTimeHours / 7.0)
    }

    /// User transcribes the Apple-rendered weekly total into the app. The
    /// report extension sandbox blocks data hand-off, so this slider is the
    /// only honest channel — and the upward drag doubles as a commitment beat.
    /// Styled as a line item on the receipt (hairline divider, no card box),
    /// locked to the receipt's coral.
    private var weeklyMatchSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("Match your total")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(OB.fg3)

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(reportedWeeklyScreenTimeHours))")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(OB.coral)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.18), value: reportedWeeklyScreenTimeHours)

                    Text("h")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(OB.fg2)
                }
            }

            WeeklyHoursMatchSlider(
                value: $reportedWeeklyScreenTimeHours,
                range: 7...105,
                tint: OB.coral
            )

            HStack {
                Text("7h")
                Spacer()
                Text(weeklyDailyEquivalentLabel)
                    .foregroundStyle(OB.fg2)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: reportedWeeklyScreenTimeHours)
                Spacer()
                Text("105h")
            }
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(OB.fg3)
        }
        .opacity(screenTimeReceiptVisible ? 1 : 0)
        .offset(y: screenTimeReceiptVisible ? 0 : 14)
        .animation(.spring(response: 0.54, dampingFraction: 0.84).delay(0.12), value: screenTimeReceiptVisible)
    }

    private var screenTimeReceiptChart: some View {
        DeviceActivityReport(.screenTimeWeekly, filter: weeklyScreenTimeDeviceActivityFilter)
            .frame(height: 106)
    }

    private func screenTimeMetricBlock(eyebrow: String, value: String, suffix: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 74, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)

                Text(suffix)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var screenTimePermissionPrimer: some View {
        VStack(alignment: .leading, spacing: 14) {
            screenTimePrivateReceiptPreview

            VStack(spacing: 0) {
                permissionReasonRow(
                    icon: "waveform.path.ecg",
                    title: "Real usage",
                    detail: "No guessing, no averages."
                )
                Divider().overlay(AppColors.cardBorder.opacity(0.72))
                permissionReasonRow(
                    icon: "calendar.badge.clock",
                    title: "Lifetime math",
                    detail: "Turns today into years."
                )
                Divider().overlay(AppColors.cardBorder.opacity(0.72))
                permissionReasonRow(
                    icon: "lock.fill",
                    title: "Stays on device",
                    detail: "Private by Apple design."
                )
            }
            .padding(.horizontal, 2)
        }
    }

    private var screenTimePrivateReceiptPreview: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.cardElevated.opacity(0.88),
                            AppColors.pageBg.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.cardBorder.opacity(0.78), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(AppColors.electricViolet.opacity(0.18))
                        .frame(width: 140, height: 140)
                        .blur(radius: 40)
                        .offset(x: 44, y: -22)
                }
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(AppColors.accent.opacity(0.16))
                        .frame(width: 150, height: 150)
                        .blur(radius: 44)
                        .offset(x: -46, y: 38)
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Private Screen Time receipt")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(AppColors.accent)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Real data")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)

                        screenTimeMiniBars
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("on-device")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textTertiary)
                        Text("private")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(16)

            Image("mascot-thinking")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .shadow(color: AppColors.electricViolet.opacity(0.30), radius: 16, y: 7)
                .offset(x: 7, y: 10)
                .accessibilityHidden(true)
        }
        .frame(height: 154)
    }

    private var screenTimeMiniBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array([0.32, 0.66, 0.48, 0.86, 0.56].enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColors.electricViolet, AppColors.periwinkle],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 14, height: 48 * value)
                    .overlay(alignment: .top) {
                        if index == 3 {
                            Capsule()
                                .fill(AppColors.coral)
                                .frame(width: 14, height: 4)
                        }
                    }
            }
        }
        .frame(height: 52, alignment: .bottom)
    }

    private func permissionReasonRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    private var connectedStamp: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .bold))
            Text("Screen Time connected")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(AppColors.accent)
    }

    private var screenTimeDayStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.cardBorder.opacity(0.55))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColors.coralDeep, AppColors.coral],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * screenTimeDayUsedFraction)
                        .shadow(color: AppColors.coral.opacity(0.32), radius: 14, y: 5)
                }
            }
            .frame(height: 13)

            HStack {
                Text("\(dailyScreenTimeLabel) used")
                Spacer()
                Text(screenTimeRemainingLabel)
            }
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
        }
    }

    private func syncScreenTimeAccessOnAppear() {
        isRequestingScreenTimeAccess = true
        Task { @MainActor in
            await focusModeService.checkAuthorizationStatus()
            screenTimeAuthorized = (focusModeService.authorizationStatus == .approved)
            isRequestingScreenTimeAccess = false

            if screenTimeAuthorized {
                screenTimeAccessDenied = false
                useScreenTimeEstimate = false
                reloadScreenTimeReportProbe()
                animateScreenTimeReceipt()
            } else {
                // No auto-prompt: the system dialog only fires from the
                // "Allow Screen Time" button, after the primer has done its
                // job. A cold prompt over an unread primer tanks grant rate.
                screenTimeReceiptVisible = false
                useScreenTimeEstimate = false
            }
        }
    }

    /// Deep-links to the app's Settings page. FamilyControls has no direct
    /// Settings URL, so this is the closest route back for a denied user;
    /// `refreshForAppForeground()` re-checks authorization when they return.
    private func openSystemSettings() {
        trackOnboardingStepCompleted("screenTimeSettingsOpened", extraProperties: [
            "screen_time_permission": "denied"
        ])
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestScreenTimeForOnboarding() {
        isRequestingScreenTimeAccess = true
        Task { @MainActor in
            await focusModeService.requestAuthorization()
            screenTimeAuthorized = (focusModeService.authorizationStatus == .approved)
            isRequestingScreenTimeAccess = false
            if screenTimeAuthorized {
                screenTimeAccessDenied = false
                useScreenTimeEstimate = false
                reloadScreenTimeReportProbe()
                trackOnboardingStepCompleted("screenTimePermissionApproved", extraProperties: [
                    "screen_time_permission": "approved"
                ])
                animateScreenTimeReceipt()
            } else {
                screenTimeAccessDenied = true
                useScreenTimeEstimate = false
                trackOnboardingStepCompleted("screenTimePermissionDenied", extraProperties: [
                    "screen_time_permission": "denied"
                ])
            }
        }
    }

    private func animateScreenTimeReceipt() {
        screenTimeReceiptVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard screenTimeAuthorized else { return }
            screenTimeReceiptVisible = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
    }

    private func screenTimeReasonRow(title: String, detail: String, isConfirmed: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                if isConfirmed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(AppColors.accent)
                } else {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: AppColors.accent.opacity(0.55), radius: 8)
                }
            }
            .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 16)
    }

    // MARK: - Empathy Page

    private var empathyPage: some View {
        ZStack {
            EmpathySignalBackdrop(signalBroken: empathySignalBroken)
                .opacity(empathySceneVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.55), value: empathySceneVisible)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                EmpathyFeedWallScene(sceneVisible: empathySceneVisible, feedMuted: empathySignalBroken)
                    .frame(height: 306)
                    .padding(.top, 0)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: -8) {
                        Text("Your brain")
                        Text("isn't broken.")
                    }
                    .font(.brand(size: 38, weight: .heavy))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(empathyCopyVisible ? 1 : 0)
                    .offset(y: empathyCopyVisible ? 0 : 10)

                    Text("It's been hijacked.")
                        .font(.brand(size: 38, weight: .heavy))
                        .foregroundStyle(AppColors.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(empathySignalBroken ? 1 : 0.97, anchor: .leading)
                        .opacity(empathySignalBroken ? 1 : 0)

                    Text("You're not weak. You're outgunned. Memo helps you take the controls back.")
                        .font(.brand(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .frame(maxWidth: 320, alignment: .leading)
                        .opacity(empathyCopyVisible ? 1 : 0)
                        .offset(y: empathyCopyVisible ? 0 : 8)
                }
                .padding(.horizontal, 28)

                Spacer()

                Button {
                    trackOnboardingStepCompleted("empathy")
                    goToPage(5)
                } label: {
                    Text("Pick my goals")
                        .gradientButton()
                }
                .accessibilityHint("Continues to the goals selection step")
                .padding(.horizontal, 32)
                .padding(.bottom, 18)
                .opacity(empathyCTAVisible ? 1 : 0)
                .offset(y: empathyCTAVisible ? 0 : 8)
            }
            .responsiveContent(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            resetEmpathyAnimation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.45)) { empathySceneVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.easeOut(duration: 0.38)) { empathyCopyVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { empathySignalBroken = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
                withAnimation(.easeOut(duration: 0.32)) { empathyCTAVisible = true }
            }
        }
        .onDisappear(perform: resetEmpathyAnimation)
    }

    private func resetEmpathyAnimation() {
        empathySceneVisible = false
        empathySignalBroken = false
        empathyCopyVisible = false
        empathyCTAVisible = false
    }

    // MARK: - Age Page

    private var agePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 18)

                VStack(alignment: .leading, spacing: 11) {
                    Text("How many years\nare we defending?")
                        .font(.brand(size: 35, weight: .heavy))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Memo uses your age to calculate what phone time costs by 80.")
                        .font(.brand(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(agePageAppeared ? 1 : 0)
                .offset(y: agePageAppeared ? 0 : 10)

                Spacer().frame(height: 38)

                VStack(alignment: .leading, spacing: 12) {
                    AgeNumberRail(selectedAge: $selectedAge)
                        .opacity(agePageAppeared ? 1 : 0)
                        .scaleEffect(agePageAppeared ? 1 : 0.96)

                    ageProjectionStrip
                        .opacity(agePageAppeared ? 1 : 0)
                        .offset(y: agePageAppeared ? 0 : 6)

                }
                .padding(.bottom, 112)
            }
            .padding(.horizontal, 28)
            .responsiveContent(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            onboardingBottomBar {
                VStack(spacing: 12) {
                    agePrivacyLine

                    Button {
                        trackOnboardingStepCompleted("age")
                        advance(after: .age, then: 4) // play beat, then → screenTimeAccess
                    } label: {
                        Text("Check my Screen Time")
                            .gradientButton()
                    }
                    .accessibilityHint("Uses your age to personalize the next onboarding step")
                    .padding(.horizontal, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedAge = selectedAge == 0 ? 25 : selectedAge
            withAnimation(.easeOut(duration: 0.38)) {
                agePageAppeared = true
            }
        }
        .onDisappear {
            agePageAppeared = false
        }
    }

    private var agePrivacyLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Stays on your phone · Never sold")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(AppColors.textTertiary.opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(agePageAppeared ? 1 : 0)
    }

    private var ageProjectionStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(yearsUntilEighty)")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.accent)

                Text(yearsUntilEighty == 1 ? "year left in the projection" : "years left in the projection")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let trackWidth = proxy.size.width
                    let tickCount = 5

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.cardBorder.opacity(0.56))
                            .frame(height: 16)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColors.accent,
                                        AppColors.violet.opacity(0.92),
                                        AppColors.coral.opacity(0.94)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 16)
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(AppColors.textPrimary.opacity(0.18))
                                    .frame(height: 5)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 3)
                            }
                            .shadow(color: AppColors.accent.opacity(0.28), radius: 14, y: 6)

                        ForEach(1..<tickCount, id: \.self) { index in
                            Capsule()
                                .fill(AppColors.pageBg.opacity(0.58))
                                .frame(width: 2, height: 18)
                                .offset(x: trackWidth * CGFloat(index) / CGFloat(tickCount))
                        }

                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(AppColors.textPrimary.opacity(0.82), lineWidth: 2)
                            }
                            .shadow(color: AppColors.accent.opacity(0.65), radius: 12)
                            .offset(x: -1)

                        Circle()
                            .fill(AppColors.coral)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(AppColors.textPrimary.opacity(0.66), lineWidth: 2)
                            }
                            .shadow(color: AppColors.coral.opacity(0.46), radius: 12)
                            .offset(x: trackWidth - 17)
                    }
                }
                .frame(height: 24)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY")
                            .foregroundStyle(AppColors.accent)
                        Text("\(max(selectedAge, 18))")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .monospacedDigit()
                    }

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("AGE 80")
                            .foregroundStyle(AppColors.coral.opacity(0.92))
                        Text("projection")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(AppColors.textTertiary.opacity(0.58))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(AppColors.textTertiary.opacity(0.76))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.cardElevated.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.cardBorder.opacity(0.8), lineWidth: 1)
                }
        }
    }

    // MARK: - Quick Assessment Page

    private var quickAssessmentPage: some View {
        QuickAssessmentView(
            backgroundColor: $quickAssessmentBgColor,
            isInFullscreenPhase: $quickAssessmentIsFullscreen
        ) { result in
            assessmentResult = result
            trackOnboardingStepCompleted("quickAssessment")
            // Present dramatic reveal as a full-screen cover so it escapes the TabView.
            // Cover only fires from a legitimate onComplete — swiping the TabView won't trigger it.
            presentedCover = .brainAgeReveal
        }
    }

    // MARK: - Plan Reveal Page (was Personal Solution)
    //
    // Critical: this page presents the paywall on CTA. The user has now seen the
    // plan they're paying for. Paywall dismiss → focusMode setup.

    private var planRevealPage: some View {
        OnboardingPersonalSolutionView(
            userGoals: selectedGoals,
            brainAge: assessmentResult?.brainAge,
            userAge: selectedAge,
            dailyScreenTimeHours: effectiveDailyScreenTimeHours,
            projectedScreenTimeHours: projectedScreenTimeHours,
            projectionIsEstimate: projectionIsEstimate,
            receiptCount: receiptCount,
            onContinue: {
                trackOnboardingStepCompleted("planReveal")
                goToPage(5)
            }
        )
    }

    // MARK: - Notification Priming Page

    private var notificationPrimingPage: some View {
        OnboardingNotificationPrimingView { granted in
            notificationsEnabled = granted
            trackOnboardingStepCompleted("notificationPriming", extraProperties: [
                "notifications_enabled": granted
            ])
            if granted {
                NotificationService.shared.scheduleStoredTrialRemindersIfAuthorized()
            }
            onboardingCompletionQueued = true
            completeOnboarding()
        }
    }

    // MARK: - Industry Scare Page (NEW — $57B engineering spend)

    private var industryScarePage: some View {
        FocusOnboardIndustryScare {
            trackOnboardingStepCompleted("industryScare")
            goToPage(4) // → empathy
        }
    }

    // MARK: - Pain Cards Page (NEW)

    private var painCardsPage: some View {
        OnboardingPainCardsView { count in
            receiptCount = count
            trackOnboardingStepCompleted("painCards", extraProperties: [
                "selected_pain_card_count": count
            ])
            goToPage(3) // → industryScare
        }
    }

    // MARK: - Comparison Page (NEW)

    private var comparisonPage: some View {
        OnboardingComparisonView(
            pickupCount: 287,
            dailyHours: effectiveDailyScreenTimeHours,
            brainAge: assessmentResult?.brainAge,
            onContinue: {
                trackOnboardingStepCompleted("comparison")
                goToPage(5)
            }
        )
    }

    // MARK: - Differentiation Page (NEW)

    private var differentiationPage: some View {
        OnboardingDifferentiationView {
            trackOnboardingStepCompleted("differentiation")
            presentedCover = .paywall
        }
    }

    // MARK: - Commitment Page

    private var commitmentPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 46)

            Text("FINAL STEP")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(AppColors.accent)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Sign the pact.")
                    .font(.brand(size: 35, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text("Make the feed wait.")
                    .font(.brand(size: 32, weight: .heavy))
                    .foregroundStyle(AppColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.bottom, 12)

            Text("Hold the seal and your name signs the plan. Training comes before scrolling.")
                .font(.brand(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            CommitmentPactSheet(
                name: enteredName.trimmingCharacters(in: .whitespacesAndNewlines),
                isSigned: commitmentCompleted,
                signatureProgress: holdProgress,
                line1Visible: commitmentBullet1Visible,
                line2Visible: commitmentBullet2Visible,
                line3Visible: commitmentBullet3Visible,
                line4Visible: commitmentBullet4Visible,
                onHoldStart: {
                    guard !commitmentCompleted else { return }
                    if holdTimer == nil {
                        startHoldTimer()
                    }
                },
                onHoldEnd: {
                    if !commitmentCompleted {
                        cancelHoldTimer()
                    }
                }
            )
            .onAppear {
                let delays = [0.15, 0.85, 1.55, 2.25]
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[0]) {
                    withAnimation { commitmentBullet1Visible = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[1]) {
                    withAnimation { commitmentBullet2Visible = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[2]) {
                    withAnimation { commitmentBullet3Visible = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delays[3]) {
                    withAnimation { commitmentBullet4Visible = true }
                }
            }

            Spacer()

            VStack(spacing: 6) {
                if !commitmentCompleted {
                    Text("Hold the seal to sign")
                        .font(.brand(size: 22, weight: .heavy))
                        .foregroundStyle(holdProgress > 0.05 ? AppColors.accent : Color.primary)
                        .animation(.easeOut(duration: 0.15), value: holdProgress > 0.05)

                    Text("The feed doesn't get a vote.")
                        .font(.brand(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("Signed.")
                        .font(.brand(size: 22, weight: .heavy))
                        .foregroundStyle(AppColors.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text("No ads. No data sold. We don't become what we fight.")
                    .font(.brand(size: 13, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }

    private struct CommitmentPactSheet: View {
        let name: String
        let isSigned: Bool
        let signatureProgress: CGFloat
        let line1Visible: Bool
        let line2Visible: Bool
        let line3Visible: Bool
        let line4Visible: Bool
        let onHoldStart: () -> Void
        let onHoldEnd: () -> Void

        private var pactTitle: String {
            name.isEmpty ? "Memo pact" : "\(name)'s Memo pact"
        }

        private var signatureName: String {
            name.isEmpty ? "Memo trainee" : name
        }

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pactTitle)
                                .font(.brand(size: 24, weight: .heavy))
                                .foregroundStyle(.primary)

                            Text("Training first. Feed second.")
                                .font(.brand(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(isSigned ? "SIGNED" : "READY")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(isSigned ? AppColors.coral : AppColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                Capsule()
                                    .stroke((isSigned ? AppColors.coral : AppColors.accent).opacity(0.6), lineWidth: 1)
                            }
                    }
                    .padding(.bottom, 18)

                    PactDivider()

                    VStack(alignment: .leading, spacing: 0) {
                        CommitmentPactLine(isVisible: line1Visible, text: "Train before I scroll")
                        CommitmentPactLine(isVisible: line2Visible, text: "Make unlocks cost reps")
                        CommitmentPactLine(isVisible: line3Visible, text: "Bounce the apps draining me")
                        CommitmentPactLine(isVisible: line4Visible, text: "Don't let Big Social colonize my attention")
                    }

                    SignatureLine(
                        name: signatureName,
                        progress: signatureProgress,
                        isSigned: isSigned
                    )
                    .padding(.top, 10)
                }
                .padding(18)
                .padding(.bottom, 10)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppColors.cardElevated)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(AppColors.accent.opacity(0.24), lineWidth: 1.2)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(AppColors.cardBorder.opacity(0.9), lineWidth: 1)
                        }
                        .shadow(color: AppColors.accent.opacity(0.12), radius: 28, y: 14)
                }

                if isSigned {
                    Text("SIGNED")
                        .font(.system(size: 34, weight: .black, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(AppColors.coral)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.coral, lineWidth: 2)
                        }
                        .rotationEffect(.degrees(-9))
                        .offset(x: -16, y: -70)
                        .transition(.scale(scale: 1.2).combined(with: .opacity))
                }

                Image("mascot-celebrate")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                    .shadow(color: AppColors.accent.opacity(0.25), radius: 18, y: 8)
                    .offset(x: -92, y: 42)
                    .accessibilityHidden(true)

                CommitmentSeal(progress: signatureProgress, isSigned: isSigned)
                    .offset(x: 6, y: 22)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !isSigned else { return }
                                onHoldStart()
                            }
                            .onEnded { _ in
                                guard !isSigned else { return }
                                onHoldEnd()
                            }
                    )
            }
            .padding(.trailing, 8)
            .padding(.bottom, 42)
        }
    }

    private struct SignatureLine: View {
        let name: String
        let progress: CGFloat
        let isSigned: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("signature")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(.tertiary)

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let clamped = min(max(progress, 0), 1)
                    let revealWidth = max(1, width * clamped)

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(AppColors.cardBorder.opacity(0.85))
                            .frame(height: 1)
                            .offset(y: 18)

                        Text(name)
                            .font(.custom("Snell Roundhand", size: 38).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .foregroundStyle(AppColors.accent)
                            .shadow(color: AppColors.accent.opacity(0.35), radius: 10)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: isSigned ? width : revealWidth)
                            }

                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 9, height: 9)
                            .shadow(color: AppColors.accent.opacity(0.65), radius: 8)
                            .offset(x: max(0, revealWidth - 5), y: 18)
                            .opacity(isSigned || clamped <= 0.02 ? 0 : 1)
                    }
                }
                .frame(height: 52)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Signature \(name)")
        }
    }

    private struct CommitmentPactLine: View {
        let isVisible: Bool
        let text: String
        var showDivider = true

        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 20, height: 20)
                        .background {
                            Circle()
                                .fill(AppColors.accent.opacity(0.16))
                        }
                        .opacity(isVisible ? 1 : 0.18)

                    Group {
                        if isVisible {
                            TypewriterText(fullText: text, speed: 0.025)
                                .transition(.opacity)
                        } else {
                            Text(text)
                                .redacted(reason: .placeholder)
                                .opacity(0.18)
                        }
                    }
                    .font(.brand(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 11)

                if showDivider {
                    PactDivider()
                }
            }
        }
    }

    private struct PactDivider: View {
        var body: some View {
            Rectangle()
                .fill(AppColors.cardBorder.opacity(0.75))
                .frame(height: 1)
        }
    }

    private struct CommitmentSeal: View {
        let progress: CGFloat
        let isSigned: Bool

        var body: some View {
            let sealWidth: CGFloat = 118
            let sealHeight: CGFloat = 96
            let sealRotation: Angle = .degrees(-8)

            ZStack {
                ZStack {
                    SealBlobShape()
                        .fill(AppColors.accent.opacity(0.10 + 0.52 * progress))

                    SealBlobShape()
                        .stroke(AppColors.accent.opacity(isSigned ? 0.85 : 0.34 + 0.46 * progress), lineWidth: 2)

                    SealBlobShape()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .shadow(color: AppColors.accent.opacity(0.55 * progress), radius: 14 * progress)
                        .animation(.easeOut(duration: 0.08), value: progress)
                }
                .frame(width: sealWidth, height: sealHeight)
                .rotationEffect(sealRotation)
                .shadow(color: AppColors.accent.opacity(0.22 + 0.34 * progress), radius: 18 + 8 * progress, y: 8)
                .overlay {
                    if isSigned {
                        SealBlobShape()
                            .stroke(AppColors.coral.opacity(0.75), lineWidth: 2)
                            .frame(width: sealWidth - 12, height: sealHeight - 12)
                            .rotationEffect(sealRotation)
                            .transition(.opacity)
                    }
                }

                VStack(spacing: 2) {
                    if isSigned {
                        Image(systemName: "checkmark")
                            .font(.system(size: 25, weight: .heavy))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("HOLD")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(AppColors.textTertiary)

                        Text("SIGN")
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(progress > 0.08 ? .white : AppColors.accent)
                    }
                }
                .rotationEffect(.degrees(-7))
                .scaleEffect(isSigned ? 1.08 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isSigned)

            }
            .frame(width: 136, height: 118)
            .contentShape(Rectangle())
        }
    }

    private struct SealBlobShape: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width
            let h = rect.height

            var path = Path()
            path.move(to: CGPoint(x: 0.18 * w, y: 0.16 * h))
            path.addCurve(
                to: CGPoint(x: 0.62 * w, y: 0.08 * h),
                control1: CGPoint(x: 0.30 * w, y: -0.01 * h),
                control2: CGPoint(x: 0.48 * w, y: 0.02 * h)
            )
            path.addCurve(
                to: CGPoint(x: 0.92 * w, y: 0.32 * h),
                control1: CGPoint(x: 0.78 * w, y: 0.00 * h),
                control2: CGPoint(x: 0.91 * w, y: 0.15 * h)
            )
            path.addCurve(
                to: CGPoint(x: 0.84 * w, y: 0.76 * h),
                control1: CGPoint(x: 1.02 * w, y: 0.47 * h),
                control2: CGPoint(x: 0.96 * w, y: 0.66 * h)
            )
            path.addCurve(
                to: CGPoint(x: 0.45 * w, y: 0.94 * h),
                control1: CGPoint(x: 0.75 * w, y: 0.96 * h),
                control2: CGPoint(x: 0.58 * w, y: 0.98 * h)
            )
            path.addCurve(
                to: CGPoint(x: 0.10 * w, y: 0.78 * h),
                control1: CGPoint(x: 0.30 * w, y: 1.04 * h),
                control2: CGPoint(x: 0.12 * w, y: 0.96 * h)
            )
            path.addCurve(
                to: CGPoint(x: 0.18 * w, y: 0.16 * h),
                control1: CGPoint(x: -0.03 * w, y: 0.60 * h),
                control2: CGPoint(x: 0.00 * w, y: 0.32 * h)
            )
            path.closeSubpath()
            return path
        }
    }

    private func startHoldTimer() {
        guard !onboardingCompletionQueued else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                guard !onboardingCompletionQueued else {
                    cancelHoldTimer()
                    return
                }
                holdProgress += 0.05 / 3.0 // 3 seconds total
                if holdProgress.truncatingRemainder(dividingBy: 0.1) < 0.02 {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if holdProgress >= 1.0 {
                    holdProgress = 1.0
                    onboardingCompletionQueued = true
                    cancelHoldTimer()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        commitmentCompleted = true
                    }
                    trackOnboardingStepCompleted("commitment")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                        completeOnboarding()
                    }
                }
            }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
        // Don't reset progress — let users resume from where they stopped
    }

    // MARK: - Focus Mode Page

    private var focusModePage: some View {
        FocusModeSetupView(
            onComplete: {
                focusModeWasSetUp = true
                trackOnboardingStepCompleted("focusModeCompleted")
                goToPage(OnboardingPage.notificationPriming.rawValue)
            },
            onSkip: {
                trackOnboardingStepCompleted("focusModeSkipped")
                Analytics.focusSetupSkipped()
                goToPage(OnboardingPage.notificationPriming.rawValue)
            }
        )
    }

    private func continueButton(_ title: String = "Continue", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .gradientButton()
        }
        .accessibilityHint("Continues to the next step")
        .padding(.horizontal, 32)
    }

    private func onboardingBottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    OB.bg.opacity(0),
                    OB.bg
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)

            content()
                .padding(.bottom, 12)
        }
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .background(OB.bg)
    }

    private func completeOnboarding() {
        guard onboardingCompletionQueued else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let user: User
        if let existing = users.first {
            user = existing
        } else {
            user = User()
            modelContext.insert(user)
        }

        user.hasCompletedOnboarding = true
        user.username = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
        user.focusGoals = Array(selectedGoals)
        user.notificationsEnabled = notificationsEnabled
        user.userAge = selectedAge > 0 ? selectedAge : 0
        UserDefaults.standard.removeObject(forKey: "onboarding_selected_trap_apps")
        let sharedDefaults = UserDefaults(suiteName: "group.com.memori.shared")
        if hasScreenTimeInput {
            sharedDefaults?.set(effectiveDailyScreenTimeHours, forKey: "onboarding_projection_daily_hours")
            sharedDefaults?.set(projectionIsEstimate, forKey: "onboarding_projection_is_estimate")
            sharedDefaults?.set(projectedScreenTimeHours, forKey: "onboarding_projected_screen_time_hours")
        } else {
            sharedDefaults?.removeObject(forKey: "onboarding_projection_daily_hours")
            sharedDefaults?.removeObject(forKey: "onboarding_projection_is_estimate")
            sharedDefaults?.removeObject(forKey: "onboarding_projected_screen_time_hours")
        }

        // Save brain score result — assessment does NOT count toward daily session/limit
        if let result = assessmentResult {
            modelContext.insert(result)
            user.totalXP += 50  // Bonus XP for completing onboarding assessment
        }

        Analytics.onboardingCompleted(
            goals: onboardingGoalValues,
            selectedAge: collectedAgeForAnalytics,
            screenTimeHours: collectedScreenTimeHoursForAnalytics,
            screenTimeIsEstimate: collectedScreenTimeEstimateFlagForAnalytics,
            brainAge: assessmentResult?.brainAge,
            brainScore: assessmentResult?.brainScore,
            receiptCount: receiptCount,
            focusModeWasSetUp: focusModeWasSetUp,
            notificationsEnabled: notificationsEnabled,
            secondsSinceStart: onboardingElapsed,
            totalSteps: totalPages,
            variant: onboardingVariant.rawValue
        )

        try? modelContext.save()
        onComplete()
    }
}

// MARK: - Organic Circle Shape

/// Custom capsule-track slider for the weekly Screen Time match card.
/// Raw DragGesture (same precedent as AgeNumberRail) so onboarding page
/// gestures never swallow it; light haptic tick per hour like the age rail.
struct WeeklyHoursMatchSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color

    private let trackHeight: CGFloat = 12
    private let thumbSize: CGFloat = 28

    private var fraction: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - thumbSize, 1)
            let thumbX = usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(trackHeight, thumbX + thumbSize / 2), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
                    .offset(x: thumbX)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { gesture in
                        let dragFraction = min(max((gesture.location.x - thumbSize / 2) / usable, 0), 1)
                        let raw = range.lowerBound + Double(dragFraction) * (range.upperBound - range.lowerBound)
                        let stepped = raw.rounded()
                        if stepped != value {
                            value = stepped
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )
        }
        .frame(height: thumbSize)
        .accessibilityElement()
        .accessibilityLabel("Weekly Screen Time hours")
        .accessibilityValue("\(Int(value)) hours per week")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }
}

struct AgeNumberRail: View {
    @Binding var selectedAge: Int
    @State private var dragStartAge: Int?
    @State private var dragOffset: CGFloat = 0
    /// Per-tick compensation that accumulates as selectedAge changes during drag.
    /// dragOffset = rawTranslation + committedOffset. Without this separate state,
    /// reassigning dragOffset from rawTranslation every frame wiped the
    /// per-tick compensation and caused 60pt visual jumps at each age boundary.
    @State private var committedOffset: CGFloat = 0

    // Floor is 13 — the COPPA line, and TikTok's own minimum. Younger users
    // get a scarier (more honest) lifetime receipt than anyone forced to
    // lie upward to 18.
    private let range = 13...99
    private let tickWidth: CGFloat = 60

    private var isDragging: Bool { dragStartAge != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top row: lab-coat Memo on the LEFT, big age number on the RIGHT.
            HStack(alignment: .center, spacing: 0) {
                Image("mascot-lab-coat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-4))
                    .shadow(color: AppColors.accent.opacity(0.22), radius: 22, y: 10)

                Spacer(minLength: 8)

                Text("\(selectedAge)")
                    .font(.system(size: 100, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: Double(selectedAge)))
                    .shadow(color: AppColors.accent.opacity(0.28), radius: 22, y: 10)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedAge)
            }
            .padding(.trailing, 12)

            // Manual rail: stable full range, continuous offset that tracks finger
            // 1:1 during drag, snaps to selectedAge on release. Compensates dragOffset
            // when selectedAge ticks so the visual position stays continuous (no
            // jumping mid-drag). Skips animation during drag — animations queueing
            // per-tick was the original jitter source. DragGesture (vs ScrollView)
            // because the parent TabView's `scrollDisabled` blocks DragGesture but
            // not ScrollView's internal pan gesture.
            GeometryReader { geo in
                let centerX = geo.size.width / 2
                let baseOffset = centerX - (CGFloat(selectedAge - range.lowerBound) * tickWidth + tickWidth / 2)

                HStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { age in
                        railTick(age: age)
                    }
                }
                .frame(width: tickWidth * CGFloat(range.count), alignment: .leading)
                .offset(x: baseOffset + dragOffset)
                .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: selectedAge)
                .animation(isDragging ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: dragOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(railDragGesture)
            }
            .frame(height: 56)
            .clipped()
            .overlay(alignment: .bottom) {
                // Fixed center indicator — numbers scroll under it
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: 24, height: 4)
                    .offset(y: -2)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Age")
        .accessibilityValue("\(selectedAge)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selectedAge = min(range.upperBound, selectedAge + 1)
            case .decrement:
                selectedAge = max(range.lowerBound, selectedAge - 1)
            @unknown default:
                break
            }
        }
    }

    private var railDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartAge == nil {
                    dragStartAge = selectedAge
                    committedOffset = 0
                }
                let raw = value.translation.width

                // Compute target age from RAW translation relative to drag start —
                // not from selectedAge, since selectedAge moves as we tick.
                let stepsFromStart = (-raw / tickWidth).rounded()
                let candidate = clampedAge((dragStartAge ?? selectedAge) + Int(stepsFromStart))

                if candidate != selectedAge {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let ageDiff = candidate - selectedAge
                    selectedAge = candidate
                    // Accumulate compensation: when age decreases by 1, baseOffset
                    // jumps right by tickWidth. Counter that with -tickWidth here
                    // so the rail's visual position stays continuous with the finger.
                    committedOffset += CGFloat(ageDiff) * tickWidth
                }

                // Always derived from raw translation + accumulated compensation —
                // never assigned from raw alone (that was the bug).
                dragOffset = raw + committedOffset
            }
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dragStartAge = nil
                dragOffset = 0
                committedOffset = 0
            }
    }

    @ViewBuilder
    private func railTick(age: Int) -> some View {
        let isCentered = age == selectedAge
        Text("\(age)")
            .font(.system(
                size: isCentered ? 20 : 16,
                weight: isCentered ? .heavy : .semibold,
                design: .monospaced
            ))
            .foregroundStyle(
                isCentered ? AppColors.accent : AppColors.textTertiary.opacity(0.55)
            )
            .frame(width: tickWidth, height: 50)
    }

    private func clampedAge(_ age: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, age))
    }
}

struct OrganicCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY

        var path = Path()
        let points = 60
        for i in 0..<points {
            let angle = Double(i) / Double(points) * 2 * .pi
            let wobble = sin(angle * 3) * 0.06 + cos(angle * 5) * 0.04
            let r = 0.5 + wobble
            let x = cx + CGFloat(cos(angle) * r) * w
            let y = cy + CGFloat(sin(angle) * r) * h
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

struct EmpathySignalBackdrop: View {
    let signalBroken: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(
                colors: [
                    AppColors.accent.opacity(signalBroken ? 0.24 : 0.14),
                    AppColors.violet.opacity(0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 330
            )
            .frame(maxWidth: .infinity, maxHeight: 430, alignment: .topTrailing)
            .blur(radius: 10)
            .offset(y: 42)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.pageBg.opacity(0.0),
                            AppColors.pageBg.opacity(0.64),
                            AppColors.pageBg
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }
}

struct EmpathyFeedWallScene: View {
    let sceneVisible: Bool
    let feedMuted: Bool

    private let tiles: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, asset: String, rotation: Double)] = [
        (184, 8, 66, 78, AppColors.coral, "logo-tiktok", -7),
        (270, 26, 58, 70, AppColors.rose, "logo-instagram", 5),
        (222, 102, 80, 64, AppColors.violet, "logo-youtube", -4),
        (318, 112, 66, 78, AppColors.coral, "logo-snapchat", 7),
        (174, 190, 68, 76, AppColors.amber, "logo-x", 6),
        (268, 202, 84, 70, AppColors.coral, "logo-reddit", -5),
        (356, 214, 62, 74, AppColors.rose, "logo-tiktok", 4)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        AppColors.pageBg.opacity(0.0),
                        AppColors.coral.opacity(0.10),
                        AppColors.coral.opacity(0.22)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.72, height: height * 1.10)
                .blur(radius: 16)
                .offset(x: 18, y: -4)
                .opacity(sceneVisible ? 1 : 0)

                ZStack {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        FeedWallTile(
                            width: tile.w,
                            height: tile.h,
                            color: tile.color,
                            assetName: tile.asset,
                            dimmed: feedMuted
                        )
                        .rotationEffect(.degrees(tile.rotation))
                        .offset(
                            x: tile.x + (feedMuted ? 18 : 0),
                            y: tile.y + (feedMuted ? CGFloat(index % 2 == 0 ? -8 : 6) : 0)
                        )
                        .opacity(sceneVisible ? (feedMuted ? 0.54 : 0.82) : 0)
                        .blur(radius: feedMuted ? 1.1 : 0.4)
                        .animation(.easeOut(duration: 0.46).delay(Double(index) * 0.035), value: sceneVisible)
                        .animation(.easeInOut(duration: 0.55).delay(Double(index) * 0.025), value: feedMuted)
                    }
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .mask(
                    LinearGradient(
                        colors: [
                            .clear,
                            AppColors.pageBg,
                            AppColors.pageBg,
                            AppColors.pageBg.opacity(0.15)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotation3DEffect(.degrees(-18), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .offset(x: feedMuted ? 22 : 0, y: sceneVisible ? 0 : 8)

                RadialGradient(
                    colors: [
                        AppColors.accent.opacity(feedMuted ? 0.36 : 0.26),
                        AppColors.accent.opacity(0.10),
                        .clear
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 126
                )
                .frame(width: 248, height: 248)
                .position(x: 126, y: 204)
                .blur(radius: 4)
                .opacity(sceneVisible ? 1 : 0)

                Image("mascot-cool")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .rotationEffect(.degrees(-3))
                    .shadow(color: AppColors.accent.opacity(0.55), radius: 24, y: 12)
                    .shadow(color: AppColors.pageBg.opacity(0.95), radius: 14)
                    .position(x: 126, y: 206)
                    .opacity(sceneVisible ? 1 : 0)
                    .scaleEffect(sceneVisible ? 1 : 0.92)
                    .animation(.spring(response: 0.44, dampingFraction: 0.78), value: sceneVisible)
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        AppColors.pageBg.opacity(0.0),
                        AppColors.pageBg.opacity(0.52),
                        AppColors.pageBg
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 130)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

struct FeedWallTile: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let assetName: String
    let dimmed: Bool

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .opacity(dimmed ? 0.34 : 0.78)
            .saturation(dimmed ? 0.65 : 1)
            .blur(radius: dimmed ? 1.2 : 0.35)
            .shadow(color: color.opacity(dimmed ? 0.18 : 0.42), radius: 22, y: 10)
            .shadow(color: AppColors.pageBg.opacity(0.88), radius: 10)
    }
}

// MARK: - Welcome Bouncer Hero (the bouncer scene composition)
//
// Memo holds the line on the left; six real social media app logos
// cascade in from the right edge, layered like a fan. Composition is
// asymmetric on purpose. After the entrance, everything is static.

private struct WelcomeBouncerHero: View {
    let appsVisible: [Bool]
    let appsLeaning: Bool
    let appsPushed: [Bool]
    let memoVisible: Bool
    let memoLeaning: Bool
    let memoShoving: Bool
    let memoEnlarged: Bool

    private struct AppSlot {
        let asset: String
        let size: CGFloat
        let rotation: Double
        let xOffset: CGFloat
        let opacity: Double
        let blur: CGFloat
    }

    private let slots: [AppSlot] = [
        AppSlot(asset: "logo-tiktok",    size: 64, rotation:  -8, xOffset:  30, opacity: 1.00, blur: 0.0),
        AppSlot(asset: "logo-instagram", size: 60, rotation:   6, xOffset:  62, opacity: 0.92, blur: 0.0),
        AppSlot(asset: "logo-snapchat",  size: 56, rotation: -12, xOffset:  94, opacity: 0.85, blur: 0.0),
        AppSlot(asset: "logo-youtube",   size: 54, rotation:   9, xOffset: 122, opacity: 0.75, blur: 0.5),
        AppSlot(asset: "logo-reddit",    size: 50, rotation:  -6, xOffset: 148, opacity: 0.62, blur: 1.0),
        AppSlot(asset: "logo-x",         size: 48, rotation:  14, xOffset: 170, opacity: 0.45, blur: 2.0),
    ]

    /// Memo's horizontal offset from his resting x:
    ///  - shoving: +30 (lurching into the apps)
    ///  - leaning: +6 (pressing into them)
    ///  - else: 0
    private var memoXOffset: CGFloat {
        if memoShoving { return 30 }
        if memoLeaning { return 6 }
        return 0
    }

    /// Memo's scale composes lean (compressed 0.97), enlarge (victory 1.2),
    /// or default 1.0. Lean and enlarge never co-occur in the timeline.
    private var memoScale: CGFloat {
        guard memoVisible else { return 0.92 }
        if memoEnlarged { return 1.2 }
        if memoLeaning { return 0.97 }
        return 1.0
    }

    var body: some View {
        ZStack(alignment: .center) {
            // App pile cascading from right-of-center; tension lean toward Memo, then shoved off-screen
            ZStack {
                ForEach(Array(slots.enumerated().reversed()), id: \.offset) { index, slot in
                    let visible = index < appsVisible.count ? appsVisible[index] : false
                    let pushed = index < appsPushed.count ? appsPushed[index] : false

                    let enterOffset: CGFloat = visible ? 0 : 120
                    // Lean toward Memo: shift left, dim, slightly tilt harder. Pushed overrides lean.
                    let leanOffset: CGFloat = (appsLeaning && !pushed) ? -8 : 0
                    let leanRotationMultiplier: Double = (appsLeaning && !pushed) ? 1.4 : 1.0
                    let leanOpacityMultiplier: Double = (appsLeaning && !pushed) ? 0.85 : 1.0

                    let pushOffset: CGFloat = pushed ? 320 : 0
                    let pushRotation: Double = pushed ? 30 : 0
                    let pushOpacityMultiplier: Double = pushed ? 0 : 1

                    WelcomeAppLogo(
                        assetName: slot.asset,
                        size: slot.size,
                        baseRotation: slot.rotation * leanRotationMultiplier + pushRotation,
                        targetOpacity: slot.opacity * leanOpacityMultiplier * pushOpacityMultiplier,
                        blur: slot.blur,
                        visible: visible
                    )
                    .offset(x: slot.xOffset + enterOffset + leanOffset + pushOffset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Memo (cool / sunglasses pose) holding the line on the left
            HStack {
                Image("mascot-cool")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .shadow(
                        color: OB.accent.opacity(memoEnlarged ? 0.45 : 0.32),
                        radius: memoEnlarged ? 36 : 28,
                        y: 12
                    )
                    .scaleEffect(memoScale)
                    .offset(x: memoXOffset)
                    .opacity(memoVisible ? 1 : 0)

                Spacer()
            }
            .padding(.leading, 8)
        }
        .frame(height: 240)
    }
}

private struct WelcomeAppLogo: View {
    let assetName: String
    let size: CGFloat
    let baseRotation: Double
    let targetOpacity: Double
    let blur: CGFloat
    let visible: Bool

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .blur(radius: blur)
            .rotationEffect(.degrees(baseRotation))
            .opacity(visible ? targetOpacity : 0)
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ColoredIconBadge(icon: icon, color: color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Screen Time Estimate Sheet
//
// Replaces the old standalone estimate page. Only appears after Screen Time
// access is denied, keeping the main path real-data-first while preserving
// momentum for users who decline permission.

struct ScreenTimeEstimateSheet: View {
    @Binding var selection: Double
    let onConfirm: () -> Void

    private let quickPicks: [Double] = [2, 4, 6, 8]

    private var selectionLabel: String {
        if selection >= 10 { return "10h+" }
        let wholeHours = Int(selection.rounded(.down))
        let minutes = Int(((selection - Double(wholeHours)) * 60).rounded())
        if minutes == 0 { return "\(wholeHours)h/day" }
        return "\(wholeHours)h \(minutes)m/day"
    }

    private var annualHoursText: String {
        Int((selection * 365).rounded()).formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(AppColors.cardBorder.opacity(0.9))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 9) {
                Text("No worries.\nEstimate it.")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Text("About how much time do you spend on your phone each day?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selectionLabel)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selection >= 5 ? AppColors.error : AppColors.accent)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Spacer(minLength: 8)

                    Text("~\(annualHoursText)h/yr")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                }

                VStack(spacing: 10) {
                    Slider(value: $selection, in: 1...10, step: 0.5)
                        .tint(selection >= 5 ? AppColors.error : AppColors.accent)
                        .accessibilityLabel("Daily phone time estimate")
                        .accessibilityValue(selectionLabel)

                    HStack {
                        Text("1h")
                        Spacer()
                        Text("10h+")
                    }
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                }

                HStack(spacing: 9) {
                    ForEach(quickPicks, id: \.self) { hours in
                        estimateChip(hours)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColors.cardElevated.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppColors.cardBorder.opacity(0.82), lineWidth: 1)
                    )
                    .shadow(color: (selection >= 5 ? AppColors.error : AppColors.accent).opacity(0.16), radius: 24, y: 12)
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Used once for this receipt · stays on your device")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.35)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(AppColors.textTertiary.opacity(0.76))
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Button(action: onConfirm) {
                Text("Use this estimate")
                    .gradientButton()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .background(AppColors.pageBg.ignoresSafeArea())
        .presentationBackground(AppColors.pageBg)
    }

    private func estimateChip(_ hours: Double) -> some View {
        let selected = abs(selection - hours) < 0.01
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                selection = hours
            }
        } label: {
            Text(hours >= 8 ? "8h+" : "\(Int(hours))h")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? AppColors.pageBg : AppColors.textPrimary.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(selected ? AppColors.accent : AppColors.cardSurface.opacity(0.86))
                        .overlay(
                            Capsule()
                                .stroke(selected ? AppColors.accent.opacity(0) : AppColors.cardBorder.opacity(0.82), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen Time Estimate Row

struct ScreenTimeEstimateRow: View {
    let hours: Double
    let isSelected: Bool
    let action: () -> Void

    private var title: String {
        hours >= 8 ? "8h+" : "\(Int(hours))h"
    }

    private var subtitle: String {
        switch hours {
        case ..<3: return "Light scroll, still worth defending"
        case ..<5: return "Average phone pace"
        case ..<7: return "Heavy feed territory"
        default: return "The algorithm is clocked in"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("\(projectedAnnualHours.formatted()) hours a year")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.cardBorder)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var projectedAnnualHours: Int {
        Int((hours * 365).rounded())
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let goal: UserFocusGoal
    let index: Int
    let isSelected: Bool
    var isCompact = false
    let action: () -> Void

    private var missionTitle: String {
        switch goal {
        case .attentionShot:    return "Uncolonized attention"
        case .screenTimeFrying: return "Your hours back"
        case .doomscrolling:    return "Sleep that survives"
        case .loseFocus:        return "Outscore the feed"
        case .forgetInstantly:  return "Memory that sticks"
        case .getSharper:       return "A sharper brain"
        }
    }

    private var missionSubtitle: String {
        switch goal {
        case .attentionShot:    return "Keep Big Social out of your focus"
        case .screenTimeFrying: return "Take time back from the feed"
        case .doomscrolling:    return "Stop the 2am scroll before it starts"
        case .loseFocus:        return "Climb while your apps wait"
        case .forgetInstantly:  return "Remember what you read and opened"
        case .getSharper:       return "Every unlock is a brain rep"
        }
    }

    private var missionNumber: String {
        String(format: "%02d", index + 1)
    }

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            ZStack(alignment: .leading) {
                HStack(spacing: isCompact ? 14 : 18) {
                    Rectangle()
                        .fill(isSelected ? AppColors.accent : Color.clear)
                        .frame(width: 3, height: isCompact ? 44 : 62)
                        .shadow(color: AppColors.accent.opacity(isSelected ? 0.45 : 0), radius: 8)

                    Text(missionNumber)
                        .font(.system(size: isCompact ? 15 : 17, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary.opacity(0.74))
                        .frame(width: isCompact ? 34 : 40, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(missionTitle)
                            .font(.system(size: isCompact ? 18 : 21, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textPrimary.opacity(0.92))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Text(missionSubtitle)
                            .font(.system(size: isCompact ? 11 : 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GoalSelectionMark(isSelected: isSelected, isCompact: isCompact)
                }
            }
            .padding(.vertical, isCompact ? 9 : 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(missionTitle), \(missionSubtitle)\(isSelected ? ", selected" : "")")
    }
}

private struct MemoLookoutHeader: View {
    var isCompact = false
    var height: CGFloat? = nil

    var body: some View {
        let resolvedHeight = height ?? (isCompact ? 92 : 118)

        Image("memo-flashlight")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: isCompact ? 202 : 265, height: resolvedHeight, alignment: .leading)
            .offset(x: isCompact ? -16 : -20)
            .shadow(color: AppColors.accent.opacity(0.28), radius: 18, y: 8)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Stack of social-media app tiles in the top-right.
// Visual story: Memo (lookout) is watching the actual apps farming you.
//
// Each tile prefers a real logo asset (e.g. "logo-tiktok") if present in
// Assets.xcassets. Falls back to a brand-colored tile with an SF Symbol
// approximation so the page never looks broken if assets are missing.
private struct FeedHeistBackdrop: View {
    var isCompact = false

    private struct FeedApp {
        let logoAsset: String          // Image asset name; renders if present
        let fallbackSymbol: String     // SF Symbol used until logoAsset is added
        let fallbackBg: AnyShapeStyle  // Brand color for the fallback tile
        let fallbackFg: Color
        let rotation: Double
        let xOffset: CGFloat
    }

    private let apps: [FeedApp] = [
        FeedApp(
            logoAsset: "logo-tiktok",
            fallbackSymbol: "music.note",
            fallbackBg: AnyShapeStyle(Color.black),
            fallbackFg: .white,
            rotation: -6,
            xOffset: 6
        ),
        FeedApp(
            logoAsset: "logo-youtube",
            fallbackSymbol: "play.rectangle.fill",
            fallbackBg: AnyShapeStyle(Color(red: 1.0, green: 0.0, blue: 0.2)),
            fallbackFg: .white,
            rotation: 5,
            xOffset: -8
        ),
        FeedApp(
            logoAsset: "logo-instagram",
            fallbackSymbol: "camera.fill",
            fallbackBg: AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.42, blue: 0.35),
                    Color(red: 0.72, green: 0.34, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )),
            fallbackFg: .white,
            rotation: -3,
            xOffset: 8
        ),
        FeedApp(
            logoAsset: "logo-snapchat",
            fallbackSymbol: "bubble.left.fill",
            fallbackBg: AnyShapeStyle(Color(red: 1.0, green: 0.99, blue: 0.0)),
            fallbackFg: .black,
            rotation: 4,
            xOffset: -6
        ),
        FeedApp(
            logoAsset: "logo-x",
            fallbackSymbol: "xmark",
            fallbackBg: AnyShapeStyle(Color.black),
            fallbackFg: .white,
            rotation: -4,
            xOffset: 2
        ),
        FeedApp(
            logoAsset: "logo-reddit",
            fallbackSymbol: "bubble.left.and.bubble.right.fill",
            fallbackBg: AnyShapeStyle(Color(red: 1.0, green: 0.27, blue: 0.0)),
            fallbackFg: .white,
            rotation: 3,
            xOffset: -4
        )
    ]

    var body: some View {
        VStack(spacing: isCompact ? 6 : 8) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                appTile(app)
            }
        }
        .rotation3DEffect(.degrees(-18), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .rotationEffect(.degrees(3))
        .frame(width: isCompact ? 104 : 132, height: isCompact ? 238 : 320)
        .mask(
            RadialGradient(
                colors: [.black, .black.opacity(0.7), .clear],
                center: .topTrailing,
                startRadius: isCompact ? 46 : 60,
                endRadius: isCompact ? 184 : 240
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func appTile(_ app: FeedApp) -> some View {
        Group {
            if UIImage(named: app.logoAsset) != nil {
                Image(app.logoAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(app.fallbackBg)
                    .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
                    .overlay(
                        Image(systemName: app.fallbackSymbol)
                            .font(.system(size: isCompact ? 15 : 18, weight: .bold))
                            .foregroundStyle(app.fallbackFg)
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
        .rotationEffect(.degrees(app.rotation))
        .offset(x: app.xOffset)
    }
}

private struct GoalSelectionMark: View {
    let isSelected: Bool
    var isCompact = false

    var body: some View {
        ZStack {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 19 : 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.accent)
                    .shadow(color: AppColors.accent.opacity(0.55), radius: 8)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(AppColors.cardBorder.opacity(0.92), lineWidth: 2)
                    .frame(width: isCompact ? 22 : 24, height: isCompact ? 22 : 24)
            }
        }
        .frame(width: isCompact ? 26 : 30, height: isCompact ? 26 : 30)
    }
}

// MARK: - Welcome Demo Bezel
//
// Phone-in-phone bezel showing the auto-looping product demo. Materializes
// after the existing WelcomeBouncerHero animation completes — metaphor (Memo
// pushing apps) hands off to receipts (real recording of the block-train-
// unlock loop). Asset: `onboarding_demo.mp4` in the main bundle. The caller
// guards transition to this bezel with a Bundle lookup, so shipping without
// the asset cleanly falls back to the bouncer-only welcome.

struct WelcomeDemoBezel: View {
    /// Drives play/pause so the AVPlayer doesn't burn cycles when the welcome
    /// page is off-screen (still in the navigation stack but not visible).
    let isActive: Bool
    var widthFraction: CGFloat = 0.55
    var maxWidth: CGFloat = 220
    var verticalOffset: CGFloat = -36
    var rotationDegrees: Double = 10

    @State private var isMuted = true

    private static let videoName = "onboarding_demo"
    private static let videoExt = "mp4"

    var body: some View {
        GeometryReader { geo in
            // PNG aspect = 450 / 920 ≈ 0.489. Use the asset's exact ratio so
            // the screen cutout matches up with the video underneath.
            // Clamp by height too so a short container can't push the phone
            // past its bounds and into the copy above or below it.
            let bezelWidth: CGFloat = min(geo.size.width * widthFraction, maxWidth, geo.size.height * (450.0 / 920.0))
            let bezelHeight: CGFloat = bezelWidth * (920.0 / 450.0)
            // The PNG's chrome is roughly 4% of width on each side. Inset the
            // video by that much so it sits flush inside the screen cutout
            // and doesn't bleed under the bezel.
            let screenInset: CGFloat = bezelWidth * 0.04
            let screenCornerRadius: CGFloat = bezelWidth * 0.12

            HStack {
                Spacer(minLength: 0)
                bezelFrame(screenInset: screenInset, screenCornerRadius: screenCornerRadius)
                    .frame(width: bezelWidth, height: bezelHeight)
                    .rotation3DEffect(
                        .degrees(rotationDegrees),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        anchor: .center,
                        anchorZ: 0,
                        perspective: 0.45
                    )
                    .shadow(color: .black.opacity(0.75), radius: 28, x: 10, y: 18)
                    .shadow(color: Color(red: 0.408, green: 0.565, blue: 0.996).opacity(0.18), radius: 36, x: 0, y: 0)
                    .offset(y: verticalOffset)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    private func bezelFrame(screenInset: CGFloat, screenCornerRadius: CGFloat) -> some View {
        ZStack {
            // Layer 1: video plays in the screen cutout area, clipped to
            // match the PNG's screen corner radius.
            LoopingVideoPlayer(
                videoName: Self.videoName,
                videoExt: Self.videoExt,
                isPlaying: isActive,
                isMuted: isMuted
            )
            .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
            .padding(screenInset)

            // Layer 2: real iPhone 17 Pro PNG with transparent screen. Sits
            // on top of the video — its transparent screen lets the video
            // show through, and the PNG provides photoreal chrome edges,
            // baked highlights, and Dynamic Island detail.
            // Loaded via UIImage explicitly because SwiftUI's `Image(_ name:)`
            // sometimes fails to resolve loose bundle PNGs that aren't part
            // of an Asset Catalog.
            if let frame = UIImage(named: "iphone17pro") {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
        }
    }
}

// Plays the demo video on a seamless loop using AVPlayerLooper. Pauses when
// `isPlaying` flips to false so backgrounded onboarding pages don't keep the
// decoder running.
private struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoExt: String
    let isPlaying: Bool
    let isMuted: Bool

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .black

        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExt) else {
            return view
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = isMuted
        queuePlayer.actionAtItemEnd = .advance

        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        context.coordinator.player = queuePlayer
        context.coordinator.looper = looper

        view.playerLayer.player = queuePlayer
        view.playerLayer.videoGravity = .resizeAspectFill

        if isPlaying {
            queuePlayer.play()
        }
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        guard let player = context.coordinator.player else { return }
        player.isMuted = isMuted
        if isPlaying {
            if player.timeControlStatus != .playing {
                player.play()
            }
        } else {
            if player.timeControlStatus != .paused {
                player.pause()
            }
        }
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
        uiView.playerLayer.player = nil
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct OnboardingTrialPrimerView: View {
    let headline: String
    let subhead: String
    let footnote: String
    let mascotName: String
    let tint: Color
    let ctaTitle: String
    let onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700

            // Headline, mascot, CTA. The terms card is gone — the headline
            // already says "$0.00" and "7 days on us", so restating it in a
            // ledger was redundant weight on the last screen before the paywall.
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: compact ? 14 : 26)

                VStack(alignment: .leading, spacing: compact ? 10 : 14) {
                    Text(headline)
                        .font(.brand(size: compact ? 34 : 44, weight: .heavy))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.74)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subhead)
                        .font(.brand(size: compact ? 18 : 22, weight: .semibold))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.32), value: appeared)

                Spacer(minLength: 12)

                Image(mascotName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: compact ? 210 : 280, maxHeight: compact ? 210 : 280)
                    .shadow(color: tint.opacity(0.34), radius: 34, x: 0, y: 20)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .animation(.spring(response: 0.58, dampingFraction: 0.80).delay(0.10), value: appeared)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 32)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // No opaque bar: nothing scrolls under the CTA any more, so a solid
            // ground here just cut a black band across the illustration.
            VStack(spacing: 10) {
                OBContinueButton(title: ctaTitle, action: onContinue)

                Text(footnote)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OB.fg3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.28).delay(0.24), value: appeared)
            .padding(.horizontal, 32)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
private extension View {
    func onboardingPreviewDependencies() -> some View {
        environment(FocusModeService())
            .environment(StoreService(loadProductsOnInit: false))
            .modelContainer(for: [
                User.self,
                Exercise.self,
                DailySession.self,
                BrainScoreResult.self,
                Achievement.self
            ], inMemory: true)
            .preferredColorScheme(.dark)
    }
}

#Preview("Onboarding · Welcome") {
    OnboardingView(startPage: 0, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Goals") {
    OnboardingView(startPage: 2, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Screen Time Access") {
    OnboardingView(startPage: 4, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Trial Trust Bridge") {
    OnboardingView(startPage: 9, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Trial Reminder Bridge") {
    OnboardingView(startPage: 10, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Final Plan Build") {
    OnboardingView(startPage: 11, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}

#Preview("Onboarding · Focus Blocking Setup") {
    OnboardingView(startPage: OnboardingPage.focusMode.rawValue, previewName: "Dylan") {}
        .onboardingPreviewDependencies()
}
#endif
