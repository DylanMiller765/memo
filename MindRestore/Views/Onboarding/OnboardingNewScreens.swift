import SwiftUI
import UIKit
import UserNotifications
import AVKit
import AVFoundation

// MARK: - Processing Moment
//
// Sits between the assessment (page 5) and the brain age reveal.
// Auto-advances after a brief delay. Makes the result feel earned.

struct OnboardingProcessingView: View {
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var statusIndex: Int = 0
    @State private var dots: String = ""

    private let statuses = [
        "Analyzing your responses",
        "Comparing to 47,000+ players",
        "Calibrating your Brain Age"
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated brain icon with pulse
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .scaleEffect(1 + progress * 0.15)
                    .opacity(1 - progress * 0.3)

                Circle()
                    .fill(AppColors.accent.opacity(0.18))
                    .frame(width: 100, height: 100)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .symbolEffect(.pulse, options: .repeating)
            }

            VStack(spacing: 14) {
                Text(statuses[statusIndex] + dots)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.2), value: statusIndex)

                ProgressView(value: progress)
                    .tint(AppColors.accent)
                    .padding(.horizontal, 60)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("Personalizing your results")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, 24)
        }
        .responsiveContent(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Smooth progress bar over ~2.5 seconds
        withAnimation(.easeInOut(duration: 2.5)) {
            progress = 1.0
        }

        // Cycle through status messages
        for (i, _) in statuses.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * 0.85)) {
                withAnimation { statusIndex = i }
            }
        }

        // Animate dots
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
            DispatchQueue.main.async {
                if dots.count < 3 {
                    dots += "."
                } else {
                    dots = ""
                }
                if progress >= 1.0 {
                    timer.invalidate()
                }
            }
        }

        // Auto-advance
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            onComplete()
        }
    }
}

// MARK: - Personal Plan Reveal
//
// Sits after the brain age reveal. Turns the user's inputs into the
// resistance plan: train, lock apps, earn unlocks, compete.

struct OnboardingPersonalSolutionView: View {
    let userGoals: Set<UserFocusGoal>
    let brainAge: Int?
    let userAge: Int
    let dailyScreenTimeHours: Double
    let projectedScreenTimeHours: Int
    let projectionIsEstimate: Bool
    let receiptCount: Int
    let onContinue: () -> Void

    private enum RevealBeat {
        case stakes
        case reclaim   // was .withMemo — Beat 1: post-cut hero + corporate punch + CTA
        case plan
    }

    @State private var cardsAppeared: [Bool] = [false, false, false, false]
    @State private var revealBeat: RevealBeat = .stakes
    @State private var headlineAppeared = false
    @State private var animatedProjectionHours = 0
    @State private var animatedReclaimedHours = 0
    @State private var revealStarted = false
    @State private var revealTask: Task<Void, Never>?
    /// Drives the backdrop's recoil + drift fade-out + opacity drop in a
    /// single animatable scalar. 0 = stakes (apps alive), 1 = reclaim
    /// (apps pushed back). Animated via withAnimation so the TimelineView
    /// inside PlanRevealBackdrop sees a smoothly interpolated value.
    @State private var recoilProgress: CGFloat = 0
    /// Slash sweep: capsule scale-x from 0 → 1 as the brand-blue cut beam
    /// crosses the projected number. Separate from slashOpacity so the
    /// capsule can fade out independently after the sweep completes.
    @State private var slashProgress: CGFloat = 0
    @State private var slashOpacity: CGFloat = 0
    /// Tracks count progress 0 → 1 so the projected-number color can
    /// interpolate coral → coralDeep continuously instead of step-by-step.
    @State private var countProgress: Double = 0
    /// Plan-beat life-bar draw-in. Animates 0 → 1 with easeOut once the
    /// plan beat appears so the 2-color bar fills in from the leading edge
    /// (saved blue → residual coral) instead of snapping in fully drawn.
    @State private var planBarProgress: CGFloat = 0
    /// Per-row glow trigger for plan-card numbers. Each row pulses brand-
    /// blue when it appears so the plan reads as "unsealed" instead of
    /// "printed."
    @State private var cardGlowing: [Bool] = [false, false, false, false]

    /// Drives the Beat 1 hero number's format. The cut snaps to .hours so
    /// the user reads continuity with the count-up; ~700ms later we flip
    /// to .breakdown ("4 YEARS · 132 DAYS") so the emotional weight lands.
    private enum HeroFormat {
        case hours
        case breakdown
    }
    @State private var heroFormat: HeroFormat = .hours

    init(
        userGoals: Set<UserFocusGoal>,
        brainAge: Int?,
        userAge: Int,
        dailyScreenTimeHours: Double,
        projectedScreenTimeHours: Int,
        projectionIsEstimate: Bool,
        receiptCount: Int,
        previewStartsAtPlan: Bool = false,
        onContinue: @escaping () -> Void
    ) {
        self.userGoals = userGoals
        self.brainAge = brainAge
        self.userAge = userAge
        self.dailyScreenTimeHours = dailyScreenTimeHours
        self.projectedScreenTimeHours = projectedScreenTimeHours
        self.projectionIsEstimate = projectionIsEstimate
        self.receiptCount = receiptCount
        self.onContinue = onContinue

        guard previewStartsAtPlan else { return }
        _cardsAppeared = State(initialValue: [true, true, true, true])
        _revealBeat = State(initialValue: .plan)
        _headlineAppeared = State(initialValue: true)
        _animatedProjectionHours = State(initialValue: projectedScreenTimeHours)
        _animatedReclaimedHours = State(initialValue: Int(Double(projectedScreenTimeHours) * Self.memoReductionFraction))
        _revealStarted = State(initialValue: true)
        _recoilProgress = State(initialValue: 1)
        _planBarProgress = State(initialValue: 1)
        _heroFormat = State(initialValue: .breakdown)
    }

    /// Top 3 solutions to mirror back. Falls back to a sensible default trio
    /// if the user skipped goal selection (so the page still has substance).
    private var solutions: [UserFocusGoal] {
        let priorityOrder: [UserFocusGoal] = [
            .screenTimeFrying, .doomscrolling, .attentionShot,
            .loseFocus, .forgetInstantly, .getSharper
        ]
        let ordered = priorityOrder.filter { userGoals.contains($0) }
        if ordered.isEmpty {
            return [.screenTimeFrying, .doomscrolling, .attentionShot]
        }
        return Array(ordered.prefix(3))
    }

    private func solutionTitle(_ goal: UserFocusGoal) -> String {
        switch goal {
        case .screenTimeFrying: return "200+ apps stay locked"
        case .doomscrolling:    return "Earn back screen time"
        case .attentionShot:    return "Rebuild your focus"
        case .loseFocus:        return "Restore concentration"
        case .forgetInstantly:  return "Sharpen recall in days"
        case .getSharper:       return "Track your Brain Age"
        }
    }

    private func solutionDetail(_ goal: UserFocusGoal) -> String {
        switch goal {
        case .screenTimeFrying: return "Until you train. No willpower required."
        case .doomscrolling:    return "Train to unlock minutes."
        case .attentionShot:    return "10 games. 5 minutes a day. That's it."
        case .loseFocus:        return "Working memory exercises rebuild it."
        case .forgetInstantly:  return "Memory drills you'll actually feel work."
        case .getSharper:       return "Daily score shows your cognitive age."
        }
    }

    private func goalColor(_ goal: UserFocusGoal) -> Color {
        switch goal {
        case .screenTimeFrying: return AppColors.coral
        case .doomscrolling:    return AppColors.violet
        case .attentionShot:    return AppColors.accent
        case .loseFocus:        return AppColors.sky
        case .forgetInstantly:  return AppColors.mint
        case .getSharper:       return AppColors.amber
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                revealBackdrop(size: proxy.size)

                Group {
                    switch revealBeat {
                    case .stakes:
                        VStack(alignment: .leading, spacing: 0) {
                            cinematicProjectionHero
                                .padding(.top, 38)
                                .opacity(headlineAppeared ? 1 : 0)
                                .offset(y: headlineAppeared ? 0 : 10)

                            Spacer(minLength: 24)

                            heroNumberBlock
                                .opacity(headlineAppeared ? 1 : 0)

                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    case .reclaim:
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)

                            VStack(alignment: .leading, spacing: 4) {
                                cinematicProjectionHero
                                heroNumberBlock
                            }

                            Spacer(minLength: 24)

                            beat1Extras
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 38)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .safeAreaInset(edge: .bottom) {
                            beat1CTAButton
                                .padding(.horizontal, 32)
                                .padding(.bottom, 16)
                                .padding(.top, 8)
                                .background(
                                    LinearGradient(
                                        colors: [AppColors.pageBg.opacity(0), AppColors.pageBg.opacity(0.85), AppColors.pageBg],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .ignoresSafeArea(edges: .bottom)
                                )
                        }
                        .transition(.opacity)
                    case .plan:
                        planBeatLayout
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(.spring(response: 0.68, dampingFraction: 0.86), value: revealBeat)
        .animation(.spring(response: 0.48, dampingFraction: 0.82), value: headlineAppeared)
        .onAppear {
            startRevealAnimation()
        }
        .onDisappear {
            revealTask?.cancel()
        }
    }

    private func revealBackdrop(size: CGSize) -> some View {
        PlanRevealBackdrop(
            isStakes: revealBeat == .stakes,
            isDefeated: revealBeat != .stakes,   // Beat 1 + Beat 2 share defeated grid
            recoilProgress: recoilProgress,
            size: size,
            logos: feedTileLogos
        )
    }

    /// Top-anchored content for the stakes/reclaim states. Pill +
    /// eyebrow + headline. The number + caption block lives in
    /// `heroNumberBlock`, which the parent positions independently
    /// (centered for stakes, tight under this view for reclaim).
    private var cinematicProjectionHero: some View {
        let isReclaim = revealBeat == .reclaim
        let eyebrowAccent = isReclaim ? AppColors.accent : AppColors.coral

        return VStack(alignment: .leading, spacing: 10) {
            // Screen Time provenance pill — only on stakes
            if !isReclaim {
                screenTimeSourcePill
                    .transition(.opacity)
            }

            // Eyebrow
            Text(isReclaim ? "WITH MEMO" : "WITHOUT MEMO")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(eyebrowAccent)
                .contentTransition(.opacity)

            // Stakes-only headline ("You're giving social media giants").
            // Fades out at the cut.
            if !isReclaim {
                Text("You're giving social\nmedia giants")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The hero number + caption stack. On stakes: animated count-up
    /// in coral with HOURS + climbing breakdown subtitle. On reclaim
    /// + .hours: snapped reclaimedHoursText with "hours back in your
    /// life" subtitle. On reclaim + .breakdown: savedBreakdownText
    /// with the same subtitle. The parent body chooses where this
    /// view sits relative to `cinematicProjectionHero` — vertically
    /// centered for stakes, tight under the eyebrow for reclaim.
    private var heroNumberBlock: some View {
        let isReclaim = revealBeat == .reclaim
        let numberAccent: Color = isReclaim
            ? AppColors.accent
            : AppColors.coral.interpolated(with: AppColors.coralDeep, by: countProgress)

        return VStack(alignment: .leading, spacing: 6) {
            heroNumber(numberAccent: numberAccent)

            if isReclaim {
                if heroFormat == .hours {
                    Text("HOURS BACK")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(AppColors.textPrimary.opacity(0.48))
                        .transition(.opacity)
                } else {
                    Text("back in your life")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.7))
                        .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOURS")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(AppColors.textPrimary.opacity(0.4))

                    Text(lifeBreakdownText)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(AppColors.coral)
                        .contentTransition(.numericText(value: Double(animatedProjectionHours)))
                }
            }
        }
    }

    /// The hero number block with the slash overlay. Two visual states:
    /// - hours form (during stakes count-up AND immediately post-cut):
    ///   shows `animatedHoursText` while .stakes, `reclaimedHoursText`
    ///   while .reclaim + .hours. Frame height locks to 122pt so the
    ///   slash overlay has consistent room across the cut animation.
    /// - breakdown form (post-dwell): shows `savedBreakdownText`. No
    ///   slash. Height is intrinsic so the subtitle sits directly
    ///   under the number — no residual 80pt of empty space.
    @ViewBuilder
    private func heroNumber(numberAccent: Color) -> some View {
        let useHoursForm = heroFormat == .hours || revealBeat == .stakes

        ZStack(alignment: .leading) {
            if useHoursForm {
                let displayText = revealBeat == .stakes ? animatedHoursText : reclaimedHoursText
                let numericValue = revealBeat == .stakes
                    ? Double(animatedProjectionHours)
                    : Double(savedHoursTotal)

                Text(displayText)
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberAccent)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: numericValue))
                    .shadow(
                        color: (revealBeat == .stakes ? AppColors.coral : AppColors.accent).opacity(0.28),
                        radius: 18, y: 8
                    )
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(AppColors.accent)
                                .frame(width: proxy.size.width, height: 8)
                                .scaleEffect(x: slashProgress, y: 1, anchor: .leading)
                                .offset(y: proxy.size.height / 2 - 4)
                                .opacity(slashOpacity)
                                .shadow(color: AppColors.accent.opacity(0.55), radius: 10, y: 0)
                        }
                        .allowsHitTesting(false)
                    }
                    .transition(.opacity)
            } else {
                // .reclaim + .breakdown — drop the slash, show breakdown text.
                Text(savedBreakdownText)
                    .font(.system(size: 39, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .shadow(color: AppColors.accent.opacity(0.32), radius: 16, y: 8)
                    .transition(.opacity)
            }
        }
        .frame(height: useHoursForm ? 122 : nil, alignment: .leading)
    }

    /// Small "● from your Screen Time" / "● estimated from your input"
    /// pill above the stakes eyebrow. Builds trust at the count-up moment.
    /// Driven by the existing `projectionIsEstimate` input.
    private var screenTimeSourcePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 5, height: 5)
            Text(projectionIsEstimate ? "estimated from your input" : "from your Screen Time")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(AppColors.textPrimary.opacity(0.4))
        }
    }

    /// Beat 2 elements that enter under the reclaimed-time hero after the cut:
    /// the corporate-attack punchline that tees up the plan.
    private var beat1Extras: some View {
        return VStack(alignment: .leading, spacing: 0) {
            // Corporate punch — the brand-voice anchor after the reclaimed time lands.
            VStack(alignment: .leading, spacing: 4) {
                Text("Big tech is colonizing\nyour attention.")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.94))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Memo helps you take it back.")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(AppColors.accent)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.10), value: revealBeat)
        }
    }

    /// Beat 1's "See the plan →" — fires advanceToPlan() (Phase 1 stub).
    private var beat1CTAButton: some View {
        Button(action: advanceToPlan) {
            HStack(spacing: 8) {
                Text("Show my plan")
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
            }
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.textPrimary.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: AppColors.accent.opacity(0.34), radius: 22, y: 10)
        }
        .buttonStyle(.plain)
    }

    /// Rev 4 plan-beat layout. Reframes the page from "Memo halves your
    /// damage (still 3 years lost)" to "Memo reclaims 4Y 132D — backed by
    /// behavioral science — want the last bit too?". The hero is the
    /// reclaim total; the 2-color life bar shows saved (blue) vs residual
    /// (coral); the explainer makes the 75% claim defensible; the
    /// Beat 2 — the plan card. No ScrollView per spec implementation note 4;
    /// fixed VStack + safeAreaInset(.bottom) for the CTA. Hero + bridge
    /// added in Phase 5.
    /// Beat 2 — the brain-trainer USP + tactical plan card + brand-voice
    /// bridge. Fixed VStack, no ScrollView. Mirrors Beat 1's safeAreaInset
    /// pattern for the CTA.
    private var planBeatLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Eyebrow
            Text("YOUR COUNTERATTACK")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(AppColors.textPrimary.opacity(0.4))

            // Hero — brain-trainer USP
            VStack(alignment: .leading, spacing: 0) {
                Text("Train first.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.94))
                Text("Unlock time after.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.accent)
            }

            // Supporting subhead
            Text("Train first, earn screen time, and keep the feed boxed out.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary.opacity(0.55))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Plan card
            planCard

            Spacer(minLength: 0)

            // Bridge — carries the corporate antagonist into Beat 2
            VStack(alignment: .leading, spacing: 4) {
                Text("Take your brain back.")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.94))
                Text("Big tech won't give it back voluntarily.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(cardsAppeared[3] ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .safeAreaInset(edge: .bottom) {
            unlockPlanButton
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .padding(.top, 8)
                .background(
                    LinearGradient(
                        colors: [AppColors.pageBg.opacity(0), AppColors.pageBg.opacity(0.85), AppColors.pageBg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
        }
    }

    /// Rev 5 tactical color-coded plan stack. No outer container box; each
    /// row is its own RoundedRectangle with a 3pt colored leading bar.
    /// Order encodes the brand story: Train (mechanism) → Earn (payoff) →
    /// Block (enforcement) → Compete (long game).
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            planCardRow(
                color: AppColors.violet,
                label: "Train",
                detail: "5 min training",
                value: "5 min/day",
                index: 0
            )
            planCardRow(
                color: AppColors.accent,
                label: "Earn",
                detail: "unlock time back",
                value: "your call",
                index: 1
            )
            planCardRow(
                color: AppColors.coral,
                label: "Block",
                detail: "apps stay sealed",
                value: "pick yours",
                index: 2
            )
            planCardRow(
                color: AppColors.amber,
                label: "Compete",
                detail: "climb the board",
                value: "live",
                index: 3
            )
        }
    }

    private var unlockPlanButton: some View {
        Button(action: onContinue) {
            HStack(spacing: 8) {
                Text("Take my brain back")
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
            }
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.textPrimary.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: AppColors.accent.opacity(0.34), radius: 22, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var brainAgeSubtitle: String {
        if let brainAge, userAge > 0 {
            let diff = brainAge - userAge
            if diff > 0 {
                return "You're not stuck with that score. Memo trains the brain and locks the noise."
            } else if diff < 0 {
                return "You're ahead. Memo helps you stay dangerous."
            } else {
                return "Memo's plan is built to push your Brain Age down."
            }
        }
        return "Block the noise. Train your brain. Earn your time back."
    }

    private var projectionSubtitle: String {
        let source = projectionIsEstimate ? "estimated \(dailyScreenTimeText)/day" : "\(dailyScreenTimeText)/day from Screen Time"
        return "\(source). \(brainAgeSubtitle)"
    }

    private var dailyScreenTimeText: String {
        String(format: "%.1fh", dailyScreenTimeHours)
    }

    private var targetProjectionHours: Int {
        projectedScreenTimeHours >= 1000
            ? Int((Double(projectedScreenTimeHours) / 1000.0).rounded()) * 1000
            : projectedScreenTimeHours
    }

    private var projectedHoursText: String {
        targetProjectionHours.formatted()
    }

    private var animatedHoursText: String {
        animatedProjectionHours.formatted()
    }

    /// Memo's reduction claim — single source of truth across this view AND
    /// the comparison page (next page in the funnel). Bumped from 0.50 →
    /// 0.75 so the user sees an aspirational reclaim, not "still wasting 3
    /// years." Industry baseline is 70-90% (Opal, Brick, ScreenZen) — 0.75
    /// is conservative even by category standard.
    static let memoReductionFraction: Double = 0.75

    /// Hours Memo gives back when the user follows the plan. This is the
    /// hero number on the plan beat — "RECLAIMED X YEARS Y DAYS."
    private var savedHoursTotal: Int {
        Int(Double(targetProjectionHours) * Self.memoReductionFraction)
    }

    /// Hours still given to social media giants under the Memo plan.
    /// Surfaced as a small footnote ("still: X YEARS Y DAYS on the table")
    /// so the user feels there's more to take back.
    private var residualHoursTotal: Int {
        targetProjectionHours - savedHoursTotal
    }

    private var reclaimedHoursText: String {
        max(animatedReclaimedHours, savedHoursTotal).formatted()
    }

    private var finalReclaimedHoursText: String {
        savedHoursTotal.formatted()
    }

    /// "4 YEARS · 132 DAYS" — what Memo reclaims. Hero on the plan beat.
    private var savedYears: Int { (savedHoursTotal / 24) / 365 }
    private var savedRemainingDays: Int { (savedHoursTotal / 24) - (savedYears * 365) }
    private var savedBreakdownText: String {
        "\(savedYears) YEARS · \(savedRemainingDays) DAYS"
    }

    /// "1 YEAR · 166 DAYS" — what's still on the table. Plan-beat footnote.
    private var residualYears: Int { (residualHoursTotal / 24) / 365 }
    private var residualRemainingDays: Int { (residualHoursTotal / 24) - (residualYears * 365) }
    private var residualBreakdownText: String {
        "\(residualYears) \(residualYears == 1 ? "YEAR" : "YEARS") · \(residualRemainingDays) DAYS"
    }

    private var projectedYearsText: String {
        String(format: "%.1f", Double(projectedScreenTimeHours) / 8760.0)
    }

    /// Years portion of the live-counting hours total. Updates in lockstep
    /// with the count-up so the bar + breakdown line all climb together.
    /// Ignores leap years (~0.07% off, invisible at this scale).
    private var animatedYears: Int {
        let totalDays = animatedProjectionHours / 24
        return totalDays / 365
    }

    /// Remainder days after subtracting whole years.
    private var animatedRemainingDays: Int {
        let totalDays = animatedProjectionHours / 24
        return totalDays - (animatedYears * 365)
    }

    /// "5 YEARS · 292 DAYS" — climbs alongside the projected number.
    private var lifeBreakdownText: String {
        "\(animatedYears) YEARS · \(animatedRemainingDays) DAYS"
    }

    /// Real social-app logos for the backdrop tile grid. Twelve brands now
    /// (six original PNGs + six color SVGs) — enough variety that the 77-tile
    /// grid reads as a feed wall, not a wallpaper pattern.
    private var feedTileLogos: [String] {
        [
            "logo-tiktok", "logo-instagram", "logo-youtube",
            "logo-snapchat", "logo-reddit", "logo-x",
            "logo-facebook", "logo-pinterest", "logo-threads",
            "logo-discord", "logo-twitch", "logo-bluesky"
        ]
    }

    private func startRevealAnimation() {
        guard !revealStarted else { return }
        revealStarted = true

        // Reset siege-animation state so a re-entry replays cleanly.
        recoilProgress = 0
        slashProgress = 0
        slashOpacity = 0
        countProgress = 0
        planBarProgress = 0
        heroFormat = .hours
        cardGlowing = [false, false, false, false]

        revealTask?.cancel()
        revealTask = Task { @MainActor in
            // 400ms buffer so the count-up doesn't tick during the page
            // transition's 0.40s dissolve. See:
            // docs/superpowers/specs/2026-04-28-onboarding-page-transitions-design.md
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.36)) {
                headlineAppeared = true
            }

            await countProjection()
            guard !Task.isCancelled else { return }

            // 600ms hold post-climb (down from 900ms). The drift continues
            // and the number's color settles to full coralDeep — motion stays
            // present, no dead frames.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }

            // The cut. Rev 5 sequence:
            // (1) recoil + slash sweep at slash-start (concurrent, no revealBeat change yet)
            // (2) at +0.8s, number snaps AND revealBeat flips to .reclaim in same withAnimation block
            // (3) at +1.10s, slash fades + planBarProgress draws in + Beat 1 elements enter
            // (4) at +1.50s, heroFormat flips to .breakdown
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Slash + recoil — independent of revealBeat. Apps recoil while the
            // hero block is still showing the stakes count.
            withAnimation(.easeOut(duration: 0.5)) {
                slashProgress = 1.0
                slashOpacity = 1.0
            }
            withAnimation(.spring(response: 1.2, dampingFraction: 0.86)) {
                recoilProgress = 1.0
            }

            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }

            // Number snap + layout swap to .reclaim in the SAME withAnimation
            // block — the eyebrow / subtitle / headline crossfades all ride
            // this spring. heroFormat stays .hours so the snapped number
            // renders as `38,000` (continuity with the count-up).
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                animatedReclaimedHours = savedHoursTotal
                revealBeat = .reclaim
            }

            // 300ms breath, then slash fades + Beat 1 elements draw in
            // (lifeBar via planBarProgress). See spec animation table at
            // t=7.12s relative to page-enter.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.4)) {
                slashOpacity = 0
            }
            withAnimation(.easeOut(duration: 0.6)) {
                planBarProgress = 1
            }

            // 400ms more — slash fade is finishing — then flip the hero
            // number from .hours to .breakdown. Total post-snap dwell = 700ms.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.4)) {
                heroFormat = .breakdown
            }

            // startRevealAnimation EXITS here — Beat 1 dwells until user
            // taps "See the plan →", which calls advanceToPlan().
        }
    }

    @MainActor
    private func countProjection() async {
        let target = targetProjectionHours
        // ~5.0s total count-up (was ~4.0s). 209 steps × 24ms — the rev 4
        // reframe leans on the climb to *earn* the cut, so it gets more
        // breathing room. Tick frequency (step % 24) still gives ~7
        // drumbeat haptics across the climb.
        let steps = 209
        let lightTick = UIImpactFeedbackGenerator(style: .light)
        lightTick.prepare()

        for step in 0...steps {
            guard !Task.isCancelled else { return }
            let progress = Double(step) / Double(steps)
            let eased = 1 - pow(1 - progress, 3)
            animatedProjectionHours = Int((Double(target) * eased).rounded())
            // countProgress drives the projected-number color blend
            // (coral → coralDeep) via cinematicProjectionHero.
            countProgress = eased

            // Light haptic tick every 24 steps — ~7 taps across the climb.
            // Spaces them out enough that they read as drumbeats, not buzz.
            if step > 0 && step % 24 == 0 {
                lightTick.impactOccurred(intensity: 0.4)
            }

            try? await Task.sleep(for: .milliseconds(24))
        }
    }

    /// Beat 1 → Beat 2 transition, fired by Beat 1's "See the plan →" CTA.
    /// Wired in Phase 3. Defined here in Phase 1 to keep the diff in
    /// each phase tight.
    @MainActor
    private func advanceToPlan() {
        guard revealBeat == .reclaim else { return }
        withAnimation(.spring(response: 0.74, dampingFraction: 0.86)) {
            revealBeat = .plan
        }
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            await revealPlanRows()
        }
    }

    @MainActor
    private func revealPlanRows() async {
        // Soft success haptic when the first plan row lands — completes
        // the haptic arc: light ticks during climb → medium impact at cut →
        // soft success at the counterattack reveal.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        for i in 0..<cardsAppeared.count {
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                cardsAppeared[i] = true
                if i < cardGlowing.count {
                    cardGlowing[i] = true
                }
            }
            // Each row's leading number pulses brand-blue for ~250ms then
            // settles. Gives the rows an "unsealed" feel rather than a
            // static printed list.
            Task { @MainActor [i] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    if i < cardGlowing.count {
                        cardGlowing[i] = false
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(86))
        }
    }

    /// Single row card. Row-color@10% background, 3pt leading bar in
    /// row-color, label + detail stack on the leading edge, mono value
    /// trailing. Reuses cardsAppeared[index] for the entry animation.
    @ViewBuilder
    private func planCardRow(
        color: Color,
        label: String,
        detail: String,
        value: String,
        index: Int
    ) -> some View {
        let appeared = index < cardsAppeared.count ? cardsAppeared[index] : true

        HStack(spacing: 12) {
            Rectangle()
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(detail)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 11)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.trailing, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }
}

// MARK: - LifeBar
//
// Two-color life bar shown on the plan beat. The leading section is brand
// blue (what Memo reclaims, sized via `savedFraction`); the trailing section
// is muted coral (what's still on the table). Both sections are scaled by
// `progress` (0 → 1) so the bar draws in from the leading edge after the
// plan beat appears.

private struct LifeBar: View {
    let savedFraction: CGFloat
    let progress: CGFloat
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let p = max(0, min(1, progress))
        let saved = max(0, min(1, savedFraction))
        let savedWidth = width * saved * p
        let residualWidth = width * (1 - saved) * p

        return HStack(spacing: 0) {
            LinearGradient(
                colors: [AppColors.accent.opacity(0.85), AppColors.accent],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: savedWidth, height: height)

            AppColors.coral.opacity(0.55)
                .frame(width: residualWidth, height: height)

            Spacer(minLength: 0)
        }
        .frame(width: width, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
    }
}

// MARK: - PlanRevealBackdrop ("The Siege")
//
// Single-TimelineView backdrop for the plan-reveal page. Renders a 7×5 grid
// of social-app logos with three behaviors:
//
// 1. **Drift** — per-tile sin/cos offsets driven from one timeline value
//    (no 35 independent state animations). Reads as the algorithm always-on.
// 2. **Pulse** — smooth ~1.5s sine-wave opacity breath, phase-shifted per tile
//    so the wave rolls across the grid instead of all tiles flashing in sync.
// 3. **Recoil** — when `recoilProgress` animates 0 → 1 (driven by the parent's
//    withAnimation block on the stakes → reclaim transition), tiles push
//    outward from center, drift fades, opacity halves, saturation drops.
//
// Tile depth is a continuous gradient (not three discrete bands) by
// distance from grid center — front-most tiles are sharp + opaque, edge
// tiles are dim + blurred. Reads as "feed wall in the fog."

private struct PlanRevealBackdrop: View {
    let isStakes: Bool
    let isDefeated: Bool   // true when revealBeat != .stakes — apps recoiled, dim grid
    /// 0 = full drift / pulse / opacity (apps alive). 1 = recoiled, halved
    /// opacity, drift muted (apps defeated). Animated by the parent.
    let recoilProgress: CGFloat
    let size: CGSize
    let logos: [String]

    private let rows = 11
    private let cols = 7
    private let tileSpacing: CGFloat = 10
    private let nominalTileSize: CGFloat = 28

    /// Deterministic permutation of the logo array, expanded to fill all
    /// `rows * cols` tiles. Replaces a naive `index % logos.count` mapping
    /// (which produced visible row/column patterns) with a shuffled
    /// sequence seeded from a fixed value, so the same view re-renders
    /// identically across frames but reads as varied across the grid.
    private var permutedLogos: [String] {
        let total = rows * cols
        var rng = LinearCongruentialRNG(seed: 0xA17C0DE)
        var output: [String] = []
        output.reserveCapacity(total)
        var pool: [String] = []
        while output.count < total {
            if pool.isEmpty {
                pool = logos.shuffled(using: &rng)
            }
            output.append(pool.removeLast())
        }
        return output
    }

    private var maxDist: Double {
        let centerRow = Double(rows - 1) / 2.0
        let centerCol = Double(cols - 1) / 2.0
        return sqrt(centerRow * centerRow + centerCol * centerCol)
    }

    private var accent: Color {
        isStakes ? AppColors.coral : AppColors.accent
    }

    var body: some View {
        ZStack {
            AppColors.pageBg

            // Glow halo behind the grid — color shifts from coral (stakes)
            // to accent (reclaim / plan).
            Circle()
                .fill(accent.opacity(isDefeated ? 0.14 : 0.24))
                .frame(width: size.width * 0.95, height: size.width * 0.95)
                .blur(radius: 76)
                .offset(x: size.width * 0.34, y: isStakes ? size.height * 0.12 : -size.height * 0.05)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                tileGrid(at: t)
            }
            .rotationEffect(.degrees(-8))
            .offset(x: size.width * 0.2, y: isStakes ? size.height * 0.18 : size.height * 0.08)
            .opacity(isDefeated ? 0.45 : 1)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func tileGrid(at t: Double) -> some View {
        // 6s drift period for x; 7.5s for y (slightly off so the pattern
        // never looks like rigid linear motion). 1.5s breath for pulse.
        let driftFreqX = 2.0 * .pi / 6.0
        let driftFreqY = 2.0 * .pi / 7.5
        let breathFreq = 2.0 * .pi / 1.5
        let centerRow = Double(rows - 1) / 2.0
        let centerCol = Double(cols - 1) / 2.0
        let permuted = permutedLogos

        VStack(spacing: tileSpacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: tileSpacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        tile(row: row, col: col, t: t,
                             logoName: permuted[row * cols + col],
                             driftFreqX: driftFreqX,
                             driftFreqY: driftFreqY,
                             breathFreq: breathFreq,
                             centerRow: centerRow,
                             centerCol: centerCol)
                    }
                }
                .offset(x: row.isMultiple(of: 2) ? 12 : -6)
            }
        }
    }

    @ViewBuilder
    private func tile(
        row: Int,
        col: Int,
        t: Double,
        logoName: String,
        driftFreqX: Double,
        driftFreqY: Double,
        breathFreq: Double,
        centerRow: Double,
        centerCol: Double
    ) -> some View {
        let dx = Double(row) - centerRow
        let dy = Double(col) - centerCol
        let dist = sqrt(dx * dx + dy * dy)
        let normDist = dist / maxDist  // 0 (center) → 1 (corner)

        // Continuous depth gradient — front tiles are sharp + opaque,
        // edge tiles fade into atmosphere. Rev 4 trim: peak drops 0.55 →
        // 0.40 so stakes copy reads cleanly without the grid muddying it.
        let baseOpacity = 0.40 - normDist * 0.27     // 0.40 → 0.13
        let baseBlur = normDist * 2.2                // 0pt → 2.2pt
        let baseScale = 1.0 - normDist * 0.15        // 1.0 → 0.85

        // Per-tile phase so motion isn't synchronized across the grid.
        let phase = Double(row * cols + col) * 0.7

        // Drift fades as recoil takes over — at recoilProgress=1 there's
        // effectively no drift left.
        let driftMul = max(0.0, 1.0 - Double(recoilProgress) * 1.5)
        let stakesGate = isStakes ? 1.0 : 0.0
        let driftX = sin(t * driftFreqX + phase) * 4.0 * driftMul * stakesGate
        let driftY = cos(t * driftFreqY + phase) * 3.0 * driftMul * stakesGate

        // Pulse fades on the same curve as drift — apps stop breathing
        // when defeated.
        let pulse = sin(t * breathFreq + phase * 0.3) * 0.08 * driftMul * stakesGate

        // Recoil: push outward from center by 30pt × normDist × progress.
        let unitX = dist > 0.001 ? dy / dist : 0     // dy = column delta = horizontal axis
        let unitY = dist > 0.001 ? dx / dist : 0     // dx = row delta = vertical axis
        let recoilX = unitX * 30.0 * normDist * Double(recoilProgress)
        let recoilY = unitY * 30.0 * normDist * Double(recoilProgress)

        // Combined opacity: base × pulse × recoil-halve × plan-fade.
        let recoilOpacityMul = 1.0 - 0.5 * Double(recoilProgress)
        // Rev 4: plan beat pushes the grid further into the background
        // (0.45 → 0.20) so the new RECLAIMED hero + 2-color life bar own
        // the focus. Effective max ~0.40 × 0.20 = 0.08.
        let planOpacityMul = isDefeated ? 0.20 : 1.0
        let opacity = (baseOpacity + pulse) * recoilOpacityMul * planOpacityMul

        Image(logoName)
            .resizable()
            .scaledToFit()
            .frame(width: nominalTileSize, height: nominalTileSize)
            .scaleEffect(baseScale)
            .opacity(opacity)
            .blur(radius: baseBlur + Double(recoilProgress) * 0.8)
            .saturation(1.0 - Double(recoilProgress) * 0.45)
            .offset(x: CGFloat(driftX + recoilX), y: CGFloat(driftY + recoilY))
    }
}

// MARK: - Notification Priming
//
// Sells the value of notifications BEFORE the system prompt fires.
// Cold prompts convert at ~40%; primed prompts at 70-80%+.

struct OnboardingNotificationPrimingView: View {
    let onResult: (Bool) -> Void

    @State private var headlineVisible = false
    @State private var feedCardVisible = false
    @State private var memoCardVisible = false
    @State private var captionVisible = false
    @State private var ctaVisible = false
    @State private var requesting = false
    @State private var permissionTask: Task<Void, Never>?
    @State private var showTimeoutError = false
    /// Once the user denies notifications, iOS won't re-prompt — we have to
    /// deep-link to Settings instead.
    @State private var previouslyDenied = false

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()

            notifPrimingAtmosphere

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    OBEyebrow(text: "TWO KINDS OF NUDGES")
                    Text("One pulls you in.\nOne pulls you out.")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(1)
                        .kerning(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 8)

                Spacer(minLength: 28)

                VStack(spacing: 18) {
                    NotifMockupCard(
                        variant: .feed,
                        appIcon: Image("logo-tiktok"),
                        appName: "TikTok",
                        bodyText: "🔥 Your For You page is moving. Come see what you missed."
                    )
                    .opacity(feedCardVisible ? 0.55 : 0)
                    .scaleEffect(feedCardVisible ? 0.97 : 0.92)
                    .rotationEffect(.degrees(feedCardVisible ? -3 : 0))
                    .offset(y: feedCardVisible ? 0 : -40)

                    NotifMockupCard(
                        variant: .memo,
                        appIcon: Image("app-icon"),
                        appName: "Memo",
                        bodyText: "You earned 12 min of TikTok. Tap to unlock."
                    )
                    .opacity(memoCardVisible ? 1 : 0)
                    .rotationEffect(.degrees(memoCardVisible ? 1 : 0))
                    .offset(y: memoCardVisible ? 0 : 30)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("The feed nudges to pull you back. Memo nudges to give you time back.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .heavy))
                        Text("No spam. Just unlocks, streak saves, and patrol reminders.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(OB.fg3)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
                .opacity(captionVisible ? 1 : 0)
                .offset(y: captionVisible ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if previouslyDenied {
                    Text("Permission was denied earlier — open Settings to enable.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .multilineTextAlignment(.center)
                } else if showTimeoutError {
                    Text("Couldn't request permission. Tap to retry.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.coral)
                        .multilineTextAlignment(.center)
                }

                Button {
                    if previouslyDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        requestPermission()
                    }
                } label: {
                    Group {
                        if requesting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(OB.accent, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            Text(buttonTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(OB.accent, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(requesting)

                Button {
                    Analytics.onboardingStep(step: "notificationsSkipped")
                    permissionTask?.cancel()
                    onResult(false)
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OB.fg2)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .opacity(ctaVisible ? 1 : 0)
            .offset(y: ctaVisible ? 0 : 8)
        }
        .preferredColorScheme(.dark)
        .onDisappear { permissionTask?.cancel() }
        .onAppear { startEntrance() }
    }

    private var notifPrimingAtmosphere: some View {
        ZStack {
            Circle()
                .fill(OB.accent.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 76)
                .offset(x: 130, y: -200)

            Circle()
                .fill(OB.coral.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -140, y: 220)
        }
    }

    private func startEntrance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeOut(duration: 0.4)) { headlineVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                feedCardVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78)) {
                memoCardVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.20) {
            withAnimation(.easeOut(duration: 0.35)) { captionVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeOut(duration: 0.4)) { ctaVisible = true }
        }
        // Detect previously-denied so we can offer Settings deep-link instead
        // of a no-op system prompt.
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                previouslyDenied = (settings.authorizationStatus == .denied)
            }
        }
    }

    private var buttonTitle: String {
        if previouslyDenied { return "Open Settings" }
        if showTimeoutError { return "Try Again" }
        return "Let Memo nudge me"
    }

    private func requestPermission() {
        requesting = true
        showTimeoutError = false
        permissionTask?.cancel()
        permissionTask = Task {
            // Race the permission request against an 8s timeout. If the system
            // prompt hangs (rare but possible), we surface a retry instead of
            // leaving the user stuck on a spinner.
            let granted: Bool? = await withTaskGroup(of: Bool?.self) { group in
                group.addTask {
                    await NotificationService.shared.requestPermission()
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(8))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            if Task.isCancelled { return }

            await MainActor.run {
                requesting = false
                if let granted {
                    Analytics.onboardingStep(step: granted ? "notificationsEnabled" : "notificationsDeclined")
                    onResult(granted)
                } else {
                    Analytics.onboardingStep(step: "notificationsTimeout")
                    withAnimation { showTimeoutError = true }
                }
            }
        }
    }
}

// MARK: - Notification Card Mockup
//
// File-local lock-screen-style notification mockup used by
// OnboardingNotificationPrimingView. Two variants: dimmed/tilted "feed"
// (the algorithmic enemy) vs bright "memo" (the bouncer). Built fresh
// rather than extracted to Components/ — onboarding-only.

private struct NotifMockupCard: View {
    enum Variant { case feed, memo }

    let variant: Variant
    let appIcon: Image
    let appName: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            appIcon
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(appName)
                        .font(.brand(size: 14, weight: .heavy))
                        .foregroundStyle(variant == .memo ? OB.fg : OB.fg2)

                    Spacer()

                    Text("now")
                        .font(.brand(size: 12, weight: .medium))
                        .foregroundStyle(OB.fg3)
                }

                Text(bodyText)
                    .font(.brand(size: 14, weight: variant == .memo ? .bold : .medium))
                    .foregroundStyle(variant == .memo ? OB.fg : OB.fg2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(OB.surface)

                if variant == .memo {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(OB.accent.opacity(0.05))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    variant == .memo
                        ? OB.accent.opacity(0.35)
                        : Color.white.opacity(0.06),
                    lineWidth: variant == .memo ? 1.5 : 1
                )
        }
        .shadow(
            color: variant == .memo ? OB.accent.opacity(0.32) : .clear,
            radius: variant == .memo ? 24 : 0,
            y: variant == .memo ? 10 : 0
        )
    }
}



#Preview("Personal Solution — 3 goals") {
    OnboardingPersonalSolutionView(
        userGoals: [.screenTimeFrying, .doomscrolling, .attentionShot],
        brainAge: 35,
        userAge: 28,
        dailyScreenTimeHours: 4.3,
        projectedScreenTimeHours: 50200,
        projectionIsEstimate: false,
        receiptCount: 4,
        onContinue: {}
    )
}

#Preview("Personal Solution — no goals (fallback)") {
    OnboardingPersonalSolutionView(
        userGoals: [],
        brainAge: nil,
        userAge: 0,
        dailyScreenTimeHours: 4,
        projectedScreenTimeHours: 51100,
        projectionIsEstimate: true,
        receiptCount: 0,
        onContinue: {}
    )
}

#Preview("Plan Reveal — plan beat") {
    OnboardingPersonalSolutionView(
        userGoals: [.screenTimeFrying, .doomscrolling, .attentionShot],
        brainAge: 35,
        userAge: 28,
        dailyScreenTimeHours: 4.3,
        projectedScreenTimeHours: 50200,
        projectionIsEstimate: false,
        receiptCount: 4,
        previewStartsAtPlan: true,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}


#if DEBUG
private struct OnboardingTrapSelectionPreviewHost: View {
    @State private var selectedApps: Set<OnboardingTrapApp> = [.tiktok, .youtube, .instagram]

    var body: some View {
        OnboardingTrapSelectionView(selectedApps: $selectedApps, onContinue: {})
    }
}

#Preview("Processing") {
    OnboardingProcessingView(onComplete: {})
        .preferredColorScheme(.dark)
}

#Preview("Notification Primer") {
    OnboardingNotificationPrimingView(onResult: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Trap Selection") {
    OnboardingTrapSelectionPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("Unlock Loop Demo") {
    OnboardingUnlockLoopDemoView(
        blockedApps: [.tiktok, .youtube, .instagram],
        onStarted: {},
        onComplete: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Measured") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Years Ahead") {
    OnboardingLifeSquaresReceiptView(
        age: 20,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .yearsAhead,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Sleep Locked") {
    OnboardingLifeSquaresReceiptView(
        age: 20,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .sleepLocked,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Work Locked") {
    OnboardingLifeSquaresReceiptView(
        age: 20,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .workSchoolLocked,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Shock") {
    OnboardingLifetimeShockView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Your Time") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .yourTime,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Phone Takeover") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .phoneTakeover,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Phone Truth") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .phoneTruth,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Memo Rescue") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        isLoadingScreenTime: false,
        sourceLine: "Using your Screen Time",
        previewBeat: .rescue,
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Lifetime Cost · Loading") {
    OnboardingLifeSquaresReceiptView(
        age: 25,
        dailyScreenTimeHours: 4,
        isEstimate: false,
        isLoadingScreenTime: true,
        sourceLine: "Reading your Screen Time",
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Willpower Proof") {
    OnboardingWillpowerProofView(onContinue: {})
        .preferredColorScheme(.dark)
}

#Preview("Memo Plan") {
    OnboardingMemoPlanView(
        selectedGoals: [.screenTimeFrying, .doomscrolling, .attentionShot],
        atmosphereVisible: .constant(true),
        onContinue: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Plan Build · Screen Time Beat") {
    OnboardingPlanBuildBeatOverlay(
        beat: .screenTime,
        goals: [.screenTimeFrying, .doomscrolling, .attentionShot],
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        onAdvance: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Plan Build · Final Beat") {
    OnboardingPlanFinalBeatView(
        goals: [.screenTimeFrying, .doomscrolling, .attentionShot],
        age: 25,
        dailyScreenTimeHours: 50.2 / 7.0,
        isEstimate: false,
        onComplete: {}
    )
    .preferredColorScheme(.dark)
}
#endif

// MARK: - Shared Tokens for v2 Onboarding Pages
//
// Mirror the FO design tokens from FocusOnboardingPages.swift so the Industry
// Scare → Empathy → Goals → Pain Cards → … → Plan Reveal arc all reads as one
// coherent visual system in the dark/cool v2.0 palette.

enum OB {
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.059)         // #0A0A0F
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.122)    // #14141F
    static let border = Color.white.opacity(0.08)
    static let fg = Color.white.opacity(0.94)
    static let fg2 = Color.white.opacity(0.62)
    static let fg3 = Color.white.opacity(0.40)
    static let accent = Color(red: 0.408, green: 0.565, blue: 0.996)     // #6890FE
    static let coral = Color(red: 0.980, green: 0.420, blue: 0.349)      // #FA6B59
    static let memoPurple = Color(red: 0.722, green: 0.341, blue: 0.961) // #B857F5
    static let success = Color(red: 0.0, green: 0.820, blue: 0.620)      // #00D19E
    static let amber = Color(red: 1.0, green: 0.761, blue: 0.278)        // #FFC247
}

struct OBEyebrow: View {
    let text: String
    var color: Color = OB.accent
    var body: some View {
        Text(text)
            .font(.brand(size: 13, weight: .bold))
            .tracking(1.0)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(color)
    }
}

struct OBContinueButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(OB.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Short Conversion Onboarding Screens

/// A single question that turns a rough self-report into a one-year estimate.
/// No Screen Time permission or invented baseline is required.
struct OnboardingAttentionTimePage: View {
    @Binding var selectedHours: Double?
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingResult = false
    @State private var highlightedDays = 0.0

    private let choices: [Double] = [0.5, 1, 2, 3, 4, 5, 6]

    private func annualDays(for hours: Double) -> Int {
        Int((hours * 365 / 24).rounded())
    }

    private func choiceLabel(_ hours: Double) -> String {
        if hours == 0.5 { return "<1" }
        if hours == 6 { return "6+" }
        return "\(Int(hours))"
    }

    private func pick(_ hours: Double) {
        selectedHours = hours
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
            showingResult = true
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 1.0).delay(0.16)) {
            highlightedDays = Double(annualDays(for: hours))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your time")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(OB.accent)
                Spacer()
                Button("Skip") { onContinue() }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .buttonStyle(.plain)
                    .accessibilityHint("Continue without a time estimate")
            }
            .padding(.top, 16)

            if showingResult, let hours = selectedHours {
                resultContent(hours: hours)
                    .transition(.opacity.combined(with: .offset(y: 14)))
            } else {
                questionContent
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showingResult {
                OBContinueButton(title: "See how Memo works", action: onContinue)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(OB.bg)
            }
        }
        .onAppear {
            if let selectedHours {
                showingResult = true
                highlightedDays = Double(annualDays(for: selectedHours))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How long does the scroll get you?")
                .font(.system(size: 35, weight: .black, design: .rounded))
                .tracking(-1)
                .foregroundStyle(OB.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
                .accessibilityAddTraits(.isHeader)

            Text("Roughly how many hours a day in apps you'd rather use less?")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Spacer(minLength: 22)

            OnboardingYearDots(highlightedDays: 0)
                .frame(height: 185)
                .accessibilityHidden(true)

            Text("One year, one day at a time.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Spacer(minLength: 22)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(choices.prefix(4), id: \.self) { hourChoice($0) }
                }
                HStack(spacing: 10) {
                    ForEach(choices.suffix(3), id: \.self) { hourChoice($0) }
                }
            }
            .padding(.bottom, 26)
        }
    }

    private func hourChoice(_ hours: Double) -> some View {
        Button { pick(hours) } label: {
            VStack(spacing: 1) {
                Text(choiceLabel(hours))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(hours == 0.5 || hours == 1 ? "hour" : "hours")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
            }
            .foregroundStyle(OB.fg)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(OB.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(OB.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hours == 0.5 ? "Less than one hour" : hours == 1 ? "One hour" : hours == 6 ? "Six or more hours" : "\(Int(hours)) hours")
    }

    private func resultContent(hours: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hours == 6 ? "At that pace, that's at least" : "At that pace, that's about")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(OB.fg2)
                .padding(.top, 30)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(annualDays(for: hours))")
                    .font(.system(size: 100, weight: .black, design: .rounded))
                    .tracking(-5)
                    .foregroundStyle(OB.accent)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("full days")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            Text("in a year of scrolling.")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(OB.fg)

            Spacer(minLength: 26)

            OnboardingYearDots(highlightedDays: highlightedDays)
                .frame(height: 185)
                .accessibilityHidden(true)

            Spacer(minLength: 24)

            Text(hours == 6 ? "At least 6 hours a day" : hours == 0.5 ? "At under 1 hour a day" : "At roughly \(Int(hours)) hours a day")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(OB.fg)
            Text("An estimate from your answer about apps you'd rather use less. Memo helps you interrupt the next automatic tap.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button("Change my answer") {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showingResult = false
                    highlightedDays = 0
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(OB.accent)
            .buttonStyle(.plain)
            .padding(.top, 16)

            Spacer(minLength: 12)
        }
    }
}

private struct OnboardingYearDots: View, Animatable {
    var highlightedDays: Double

    var animatableData: Double {
        get { highlightedDays }
        set { highlightedDays = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let columns = 24
            let rows = 16
            let gap: CGFloat = 3
            let side = min(
                (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns),
                (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            )
            let gridWidth = CGFloat(columns) * side + CGFloat(columns - 1) * gap
            let gridHeight = CGFloat(rows) * side + CGFloat(rows - 1) * gap
            let origin = CGPoint(x: (size.width - gridWidth) / 2, y: (size.height - gridHeight) / 2)

            for day in 0..<365 {
                let column = day % columns
                let row = day / columns
                let rect = CGRect(
                    x: origin.x + CGFloat(column) * (side + gap),
                    y: origin.y + CGFloat(row) * (side + gap),
                    width: side,
                    height: side
                )
                let color = Double(day) < highlightedDays ? OB.coral : OB.fg.opacity(0.12)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            }
        }
    }
}

// MARK: - Short onboarding kit
//
// Shared layout pieces for the five-page onboarding (intro → why → try it →
// trial → reminder) so every page uses the same gutter, headline scale and
// pinned CTA. The CTA sitting at the same height on every page is what keeps
// the deck from feeling like it jumps between screens.

enum OBLayout {
    static let gutter: CGFloat = 24
    static let contentMaxWidth: CGFloat = 440
    /// Below this content height (iPhone SE and friends) pages switch to
    /// their compact type scale and spacing.
    static let compactHeight: CGFloat = 600

    /// Phones without a home indicator report no bottom safe area, so the
    /// pinned CTA needs its own breathing room there.
    static var bottomPadding: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return (window?.safeAreaInsets.bottom ?? 0) > 0 ? 6 : 16
    }
}

struct OBHeadline: View {
    let text: String
    var size: CGFloat = 34
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .font(.brand(size: size, weight: .heavy))
            .tracking(-0.5)
            .foregroundStyle(OB.fg)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OBBodyText: View {
    let text: String
    var size: CGFloat = 16
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(OB.fg2)
            .lineSpacing(2)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "✓ No payment due now" style line.
struct OBReassurance: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OB.success)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(OB.fg)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Pins `bar` below the page content, above the home indicator.
    func obBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            self
            bar()
        }
    }
}

/// Pinned bottom action area used by every short-onboarding page.
struct OBActionBar: View {
    let title: String
    var isEnabled: Bool = true
    var reassurance: String? = nil
    var footnote: String? = nil
    var backdrop: Color = OB.bg
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let reassurance {
                OBReassurance(text: reassurance)
            }
            OBContinueButton(title: title, action: action)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, OBLayout.gutter)
        .padding(.top, 10)
        .padding(.bottom, OBLayout.bottomPadding)
        .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2)
        .frame(maxWidth: .infinity)
        .background(backdrop)
    }
}

// MARK: 1 · Intro

/// Opens on the real product: the phone demo of Memo blocking an app and
/// the game that unlocks it. Centered so the headline, phone and CTA share
/// one axis on every phone size.
struct OnboardingIntroPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) {
                VStack(spacing: compact ? 8 : 12) {
                    OBEyebrow(text: "MEMO")
                    OBHeadline(
                        text: "The app blocker\nyou play to unlock.",
                        size: compact ? 30 : 36,
                        alignment: .center
                    )
                }
                .padding(.top, compact ? 2 : 10)

                ZStack {
                    // A blurred disc fades out well inside the column, so
                    // narrow phones don't show the glow's clipped edges.
                    Circle()
                        .fill(OB.accent.opacity(0.30))
                        .frame(width: 220, height: 220)
                        .blur(radius: 70)
                        .accessibilityHidden(true)

                    WelcomeDemoBezel(
                        isActive: isActive,
                        widthFraction: 0.8,
                        maxWidth: 272,
                        verticalOffset: 0,
                        rotationDegrees: 0
                    )
                    .accessibilityLabel("Memo demo: a blocked app opens a brain game")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, compact ? 12 : 22)
                .scaleEffect(appeared ? 1 : 0.95)
                .opacity(appeared ? 1 : 0)

                OBBodyText(
                    text: "Memo locks the apps you pick. Finish a quick brain game to open one for a few minutes.",
                    size: compact ? 15 : 16,
                    alignment: .center
                )
                .padding(.bottom, compact ? 2 : 8)
            }
            .padding(.horizontal, OBLayout.gutter)
            .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2)
            .frame(maxWidth: .infinity)
        }
        .background(OB.bg.ignoresSafeArea())
        .obBottomBar {
            OBActionBar(title: "Get started", action: onContinue)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: 2 · Why Memo

/// Names why they're here without blaming them, then hands off to the demo.
struct OnboardingMotivationBridgePage: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                OnboardingLockedAppFan(compact: compact, appeared: appeared)
                    .accessibilityHidden(true)

                VStack(spacing: compact ? 12 : 16) {
                    OBHeadline(
                        text: "You're here because your phone takes more than you want to give.",
                        size: compact ? 27 : 32,
                        alignment: .center
                    )
                    OBBodyText(
                        text: "That's not a willpower problem. These apps are built to keep you scrolling. Memo puts one quick game in the way.",
                        size: compact ? 15 : 17,
                        alignment: .center
                    )
                }
                .padding(.top, compact ? 28 : 44)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OBLayout.gutter)
            .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2)
            .frame(maxWidth: .infinity)
        }
        .background(OB.bg.ignoresSafeArea())
        .obBottomBar {
            OBActionBar(title: "See how Memo works", action: onContinue)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.82).delay(0.1)) {
                appeared = true
            }
        }
    }
}

/// Three familiar feeds, fanned out and padlocked — what Memo actually does.
struct OnboardingLockedAppFan: View {
    let compact: Bool
    let appeared: Bool

    private let apps: [(asset: String, angle: Double, x: CGFloat, y: CGFloat)] = [
        ("logo-instagram", -11, -78, 14),
        ("logo-tiktok", 0, 0, 0),
        ("logo-youtube", 11, 78, 14)
    ]

    var body: some View {
        let tile: CGFloat = compact ? 70 : 84
        ZStack {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: tile * 0.26, style: .continuous)
                        .fill(OB.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: tile * 0.26, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .overlay(
                            Image(app.asset)
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .padding(tile * 0.2)
                                .saturation(0.35)
                                .opacity(0.72)
                        )
                        .frame(width: tile, height: tile)

                    Image(systemName: "lock.fill")
                        .font(.system(size: tile * 0.17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: tile * 0.36, height: tile * 0.36)
                        .background(Circle().fill(OB.accent))
                        .overlay(Circle().stroke(OB.bg, lineWidth: 3))
                        .offset(x: tile * 0.1, y: tile * 0.1)
                }
                .rotationEffect(.degrees(appeared ? app.angle : 0))
                .offset(x: appeared ? app.x * (tile / 84) : 0, y: app.y)
                .zIndex(index == 1 ? 1 : 0)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
            }
        }
        .frame(height: tile + 30)
    }
}

// MARK: 3 · Try it

/// One interactive page in four beats: the production slot, the production
/// Visual Memory game (played until the first miss), the unlock that game
/// earns, then where the score lands on this week's real leaderboard.
/// Nothing here is submitted or unlocked for real.
struct OnboardingPlayableLoopPage: View {
    let onContinue: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(GameCenterService.self) private var gameCenterService
    @State private var stage: Stage
    @State private var landedMinutes: Int?
    @State private var levelsCleared: Int
    @State private var gameRun = 0
    @State private var board: OnboardingBoardState = .loading
    @State private var unlockRevealed = false

    private enum Stage: Int { case slot, game, unlock, rank }

    init(previewCompleted: Bool = false, previewStage: Int? = nil, onContinue: @escaping (Int) -> Void) {
        self.onContinue = onContinue
        let initial: Stage = previewStage.flatMap(Stage.init(rawValue:)) ?? (previewCompleted ? .unlock : .slot)
        _stage = State(initialValue: initial)
        _levelsCleared = State(initialValue: initial.rawValue >= Stage.unlock.rawValue ? 6 : 0)
    }

    /// The demo reel always lands on Visual Memory; the ticket shows the
    /// Great tier (LV 7), the same payout the pre-2.1.6 demo showed.
    private var payoutMinutes: Int {
        landedMinutes ?? UnlockRulebook.minutes(for: .great, isPersonalBest: false)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) {
                OnboardingTryItStepper(current: stage.rawValue, compact: compact)
                    .padding(.horizontal, OBLayout.gutter)
                    .padding(.top, compact ? 0 : 6)
                    .padding(.bottom, compact ? 14 : 20)

                switch stage {
                case .slot:
                    slotStage(compact: compact)
                        .transition(.opacity)
                case .game:
                    gameStage(compact: compact)
                        .transition(.opacity)
                case .unlock:
                    OnboardingUnlockMoment(
                        minutes: payoutMinutes,
                        compact: compact,
                        onRevealed: { unlockRevealed = true }
                    )
                    .padding(.horizontal, OBLayout.gutter)
                    .transition(.opacity)
                case .rank:
                    OnboardingLeaderboardClimb(
                        board: board,
                        level: levelsCleared,
                        compact: compact,
                        onPlayAgain: playAgain
                    )
                    .padding(.horizontal, OBLayout.gutter)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
        }
        .obBottomBar { bottomBar }
        .background {
            // Behind the pinned bar too, so the slot's glow doesn't stop at
            // a visible seam above the CTA.
            if stage == .slot {
                FocusSlotAtmosphere()
            } else {
                OB.bg.ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        // Load the board while the unlock plays so the climb starts instantly.
        .task(id: stage.rawValue >= Stage.unlock.rawValue) {
            guard stage.rawValue >= Stage.unlock.rawValue else { return }
            await loadBoard()
        }
    }

    // MARK: Stages

    private func slotStage(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OBHeadline(text: "Say you open TikTok.", size: compact ? 27 : 32)
            OBBodyText(
                text: "Memo steps in first. Spin to see which game stands between you and the feed.",
                size: compact ? 14 : 16
            )
            .padding(.top, 6)

            GeometryReader { area in
                // scaleEffect doesn't shrink layout, so size the frame to the
                // scaled machine explicitly — otherwise the 360pt machine
                // overflows narrow phones and drifts right of center.
                let scale = min(1, area.size.width / 360, area.size.height / 560)
                FocusUnlockSlotMachine(
                    mode: .demo,
                    onLanded: { _ in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                            landedMinutes = UnlockRulebook.minutes(for: .great, isPersonalBest: false)
                        }
                    }
                )
                .frame(width: 360, height: 560)
                .scaleEffect(scale)
                .frame(width: area.size.width, height: area.size.height)
            }
            .padding(.top, compact ? 4 : 12)
        }
        .padding(.horizontal, OBLayout.gutter)
    }

    private func gameStage(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Visual Memory")
                        .font(.brand(size: compact ? 24 : 28, weight: .heavy))
                        .foregroundStyle(OB.fg)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("\(payoutMinutes) MIN")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(OB.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(OB.accent.opacity(0.14)))
                        .accessibilityLabel("Worth \(payoutMinutes) minutes")
                }
                OBBodyText(
                    text: "Memorize the lit squares, then tap them. The grid keeps growing until you miss.",
                    size: compact ? 13 : 15
                )
            }
            .padding(.horizontal, OBLayout.gutter)

            VisualMemoryView(
                autoStart: true,
                isOnboardingPreview: true,
                onPreviewComplete: { finishGame() },
                onPreviewProgress: { levelsCleared = $0 }
            )
            .id(gameRun)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch stage {
        case .slot:
            if landedMinutes != nil {
                OBActionBar(title: "Play Visual Memory", backdrop: .clear) {
                    advance(to: .game)
                }
                .transition(.opacity)
            } else {
                // Hold the CTA's space so the machine doesn't resize when the
                // button appears after the reel lands.
                OBActionBar(title: "Play Visual Memory", action: {})
                    .hidden()
                    .accessibilityHidden(true)
            }
        case .game:
            EmptyView()
        case .unlock:
            OBActionBar(title: "See where you'd place", isEnabled: unlockRevealed) {
                advance(to: .rank)
            }
            .id(unlockRevealed)
        case .rank:
            OBActionBar(title: "Continue") { onContinue(levelsCleared) }
        }
    }

    // MARK: Flow

    private func advance(to next: Stage) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) {
            stage = next
        }
    }

    private func finishGame() {
        unlockRevealed = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            stage = .unlock
        }
    }

    private func playAgain() {
        levelsCleared = 0
        gameRun += 1
        advance(to: .game)
    }

    private func loadBoard() async {
        #if DEBUG
        // QA only: exercise the climb on a simulator without Game Center.
        if ProcessInfo.processInfo.arguments.contains("--sample-leaderboard") {
            let names = ["sample_ava", "sample_kai", "sample_noor", "sample_leo", "sample_mia", "sample_sol",
                         "sample_jun", "sample_ivy", "sample_rex", "sample_uma", "sample_ben", "sample_zed"]
            let scores = [14, 12, 11, 9, 8, 7, 5, 5, 4, 3, 3, 2]
            let emoji = Array(repeating: "", count: names.count)
            board = .loaded(
                entries: names.indices.map {
                    LeaderboardEntryData(rank: $0 + 1, username: names[$0], score: scores[$0], avatarEmoji: emoji[$0], level: scores[$0], isCurrentUser: false)
                },
                totalPlayers: names.count
            )
            return
        }
        #endif
        guard gameCenterService.isAuthenticated else {
            board = .unavailable
            return
        }
        if case .loaded = board { return }
        board = .loading
        let result = await gameCenterService.loadLeaderboardEntries(
            category: .visualMemory,
            timeFilter: .thisWeek,
            range: NSRange(location: 1, length: 50)
        )
        if result.error != nil {
            board = .unavailable
        } else {
            let others = result.entries.filter { !$0.isCurrentUser }.sorted { $0.rank < $1.rank }
            board = .loaded(entries: others, totalPlayers: result.totalPlayerCount)
        }
    }
}

enum OnboardingBoardState {
    case loading
    case loaded(entries: [LeaderboardEntryData], totalPlayers: Int)
    case unavailable
}

/// Spin → Play → Unlock → Rank, so the user always knows where they are.
struct OnboardingTryItStepper: View {
    let current: Int
    var compact: Bool = false
    private let labels = ["Spin", "Play", "Unlock", "Rank"]

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            ForEach(labels.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(index < current ? OB.success : (index == current ? OB.accent : OB.surface))
                            .overlay(Circle().stroke(index > current ? OB.border : .clear, lineWidth: 1))
                        if index < current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(OB.bg)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(index == current ? .white : OB.fg3)
                        }
                    }
                    .frame(width: 20, height: 20)

                    Text(labels[index])
                        .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(index <= current ? OB.fg : OB.fg3)
                        .lineLimit(1)
                        .fixedSize()
                }
                if index < labels.count - 1 {
                    Capsule()
                        .fill(index < current ? OB.success.opacity(0.7) : Color.white.opacity(0.14))
                        .frame(minWidth: 6, maxWidth: .infinity)
                        .frame(height: 2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of 4: \(labels[min(current, labels.count - 1)])")
    }
}

// MARK: Unlock moment

/// The payoff for finishing, told as the slot's ticket being cashed in:
/// the "IF YOU FINISH" ticket from the spin returns, Memo slams an EARNED
/// stamp on it, the minutes roll up like the reel, then the ticket tears
/// and its TikTok stub becomes the live pass with a real countdown.
/// Labelled as a preview — nothing is unlocked during onboarding.
struct OnboardingUnlockMoment: View {
    let minutes: Int
    let compact: Bool
    /// Live unlock (not the onboarding demo): the stub shows the app the user
    /// actually blocked, and the copy never assumes it's TikTok.
    var isLive = false
    /// Replaces "You finished the game…" (a FREE PASS finishes no game).
    var intro: String? = nil
    let onRevealed: () -> Void

    private enum Phase: Int, Comparable {
        case hidden, shown, stamped, rolled, torn
        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .hidden
    @State private var rolledMinutes = 0
    @State private var slam: CGFloat = 0
    @State private var ticketFaded = false
    @State private var startedAt: Date?
    @State private var sequence: Task<Void, Never>?

    private var heroHeight: CGFloat { compact ? 268 : 330 }
    private var ticketHeight: CGFloat { compact ? 108 : 126 }
    private var stubWidth: CGFloat { compact ? 96 : 112 }
    private var ringSize: CGFloat { compact ? 176 : 214 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                OBHeadline(text: phase >= .torn ? "Unlocked." : "Cash it in.", size: compact ? 32 : 38, alignment: .center)
                    .contentTransition(.opacity)
                OBBodyText(
                    text: phase >= .torn
                        ? "\(appName) opens for \(minutes) minutes. Then Memo locks it again."
                        : intro ?? "You finished the game, so your ticket pays out.",
                    size: compact ? 14 : 16,
                    alignment: .center
                )
                .contentTransition(.opacity)
            }
            .animation(.easeInOut(duration: 0.3), value: phase)

            Spacer(minLength: compact ? 6 : 14)

            GeometryReader { area in
                hero(width: min(area.size.width, 360))
                    .frame(width: area.size.width, height: area.size.height)
            }
            .frame(height: heroHeight)

            countdown
                .opacity(phase >= .torn ? 1 : 0)
                .offset(y: phase >= .torn ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: phase)

            Spacer(minLength: compact ? 4 : 14)
        }
        .onAppear(perform: run)
        .onDisappear { sequence?.cancel() }
    }

    // MARK: Hero

    private func hero(width: CGFloat) -> some View {
        let bodyWidth = width - stubWidth
        let ticketY: CGFloat = compact ? 34 : 44
        let stubCenterX = -width / 2 + stubWidth / 2
        let bodyCenterX = width / 2 - bodyWidth / 2
        let iconY: CGFloat = compact ? 30 : 38
        let torn = phase >= .torn

        return ZStack {
            // Payoff glow + burst, centered on where the icon lands.
            Circle()
                .fill(OB.success.opacity(0.3))
                .frame(width: ringSize * 0.9, height: ringSize * 0.9)
                .blur(radius: 50)
                .offset(y: iconY)
                .opacity(torn ? 1 : 0)
                .scaleEffect(torn ? 1 : 0.4)

            OnboardingSparkBurst(active: torn, radius: ringSize * 0.62)
                .offset(y: iconY)

            countdownRing
                .frame(width: ringSize, height: ringSize)
                .offset(y: iconY)
                .opacity(torn ? 1 : 0)


            // Ticket body: promise → EARNED → rolled minutes. Falls away on tear.
            ticketBody(width: bodyWidth)
                .offset(x: bodyCenterX + (torn ? 30 : 0), y: ticketY + (torn ? 150 : 0))
                .rotationEffect(.degrees(torn ? 16 : 0))
                .opacity(ticketFaded ? 0 : 1)

            // Ticket stub. Its background falls with the body; the icon flies on.
            OnboardingTicketPieceShape(notch: .trailing)
                .fill(OB.surface)
                .overlay(
                    OnboardingTicketPieceShape(notch: .trailing)
                        .stroke(ticketTint.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                )
                .frame(width: stubWidth, height: ticketHeight)
                .offset(x: stubCenterX - (torn ? 30 : 0), y: ticketY + (torn ? 150 : 0))
                .rotationEffect(.degrees(torn ? -14 : 0))
                .opacity(ticketFaded ? 0 : 1)

            stubIcon
                .saturation(torn ? 1 : 0)
                .opacity(torn ? 1 : 0.6)
                .scaleEffect(torn ? (compact ? 1.9 : 1.95) : 1)
                .shadow(color: .black.opacity(torn ? 0.5 : 0), radius: 18, y: 10)
                .offset(x: torn ? 0 : stubCenterX, y: torn ? iconY : ticketY)
        }
        .modifier(OnboardingShakeEffect(travel: slam))
        .opacity(phase >= .shown ? 1 : 0)
        .offset(y: phase >= .shown ? 0 : 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(torn ? "Ticket cashed in. \(appName) unlocked for \(minutes) minutes." : "Ticket for \(minutes) minutes if you finish")
    }

    private var appName: String { isLive ? "Your app" : "TikTok" }

    @ViewBuilder private var stubIcon: some View {
        if isLive {
            BlockedAppIcon(size: compact ? 58 : 66, showLock: false)
        } else {
            OnboardingAppIcon(asset: "logo-tiktok", size: compact ? 58 : 66)
        }
    }

    private var ticketTint: Color { phase >= .stamped ? OB.success : OB.accent }

    private func ticketBody(width: CGFloat) -> some View {
        ZStack {
            OnboardingTicketPieceShape(notch: .leading)
                .fill(phase >= .stamped ? OB.success.opacity(0.10) : OB.surface)
            OnboardingTicketPieceShape(notch: .leading)
                .stroke(ticketTint.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
            // Perforation the ticket tears along.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 14))
                path.addLine(to: CGPoint(x: 0, y: ticketHeight - 14))
            }
            .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 6]))
            .frame(width: width, height: ticketHeight, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase >= .stamped ? "YOU EARNED" : "IF YOU FINISH")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(phase >= .stamped ? OB.success : OB.fg2)
                    .contentTransition(.opacity)
                Text(phase >= .stamped ? OnboardingUnlockMoment.clock(rolledMinutes * 60) : "\(minutes) MIN")
                    .font(.system(size: compact ? 38 : 46, weight: .heavy, design: .monospaced))
                    .foregroundStyle(OB.fg)
                    .contentTransition(.numericText(value: Double(rolledMinutes)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)

            stamp
                .offset(x: width * 0.2, y: -ticketHeight * 0.18)
        }
        .frame(width: width, height: ticketHeight)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private var stamp: some View {
        Text("EARNED")
            .font(.system(size: compact ? 16 : 18, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(OB.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(OB.success, lineWidth: 3))
            .rotationEffect(.degrees(-12))
            .scaleEffect(phase >= .stamped ? 1 : 2.6)
            .opacity(phase >= .stamped ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: phase)
    }

    private var countdownRing: some View {
        TimelineView(.periodic(from: startedAt ?? .now, by: 1)) { context in
            let total = Double(max(1, minutes * 60))
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let remaining = max(0, total - elapsed)
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: phase >= .torn ? remaining / total : 0)
                    .stroke(OB.success, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: OB.success.opacity(0.6), radius: 10)
                    .animation(.easeOut(duration: 0.9), value: phase)
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: startedAt ?? .now, by: 1)) { context in
            let total = max(1, minutes * 60)
            let elapsed = startedAt.map { max(0, Int(context.date.timeIntervalSince($0))) } ?? 0
            let remaining = max(0, total - elapsed)
            VStack(spacing: 2) {
                Text(OnboardingUnlockMoment.clock(remaining))
                    .font(.system(size: compact ? 38 : 46, weight: .bold, design: .monospaced))
                    .foregroundStyle(OB.fg)
                    .contentTransition(.numericText(countsDown: true))
                Text(isLive ? "LEFT TO SCROLL" : "LEFT ON TIKTOK · PREVIEW")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(OB.fg3)
            }
        }
    }

    // MARK: Sequence

    private func run() {
        guard sequence == nil else { return }
        if reduceMotion {
            phase = .torn
            ticketFaded = true
            rolledMinutes = minutes
            startedAt = .now
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onRevealed()
            return
        }
        sequence = Task { @MainActor in
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            let tick = UIImpactFeedbackGenerator(style: .rigid)
            let soft = UIImpactFeedbackGenerator(style: .soft)
            heavy.prepare()
            tick.prepare()

            // 1 · The ticket from the spin comes back.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { phase = .shown }

            // 2 · The stamp slams down.
            try? await Task.sleep(for: .milliseconds(890))
            guard !Task.isCancelled else { return }
            phase = .stamped
            withAnimation(.linear(duration: 0.18)) { slam += 1 }
            heavy.impactOccurred()
            SoundService.shared.playReelLock()

            // 3 · The minutes roll up like the reel.
            try? await Task.sleep(for: .milliseconds(380))
            for value in 1...max(1, minutes) {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.12)) { rolledMinutes = value }
                tick.impactOccurred(intensity: min(1, 0.45 + Double(value) / Double(max(1, minutes)) * 0.55))
                SoundService.shared.playReelTick()
                let progress = Double(value) / Double(max(1, minutes))
                try? await Task.sleep(for: .milliseconds(Int(55 + progress * progress * 110)))
            }
            guard !Task.isCancelled else { return }
            phase = .rolled
            heavy.impactOccurred(intensity: 0.8)

            // 4 · Tear along the perforation; the stub becomes the live pass.
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            soft.impactOccurred()
            startedAt = .now
            // Fade the paper fast so its digits don't trail the tear.
            withAnimation(.easeOut(duration: 0.16)) { ticketFaded = true }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) { phase = .torn }
            try? await Task.sleep(for: .milliseconds(90))
            soft.impactOccurred(intensity: 0.7)

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            SoundService.shared.playComplete()

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            onRevealed()
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// One half of a ticket: rounded card with semicircle notches cut where the
/// two halves meet, so the perforation reads as tearable.
struct OnboardingTicketPieceShape: Shape {
    enum Notch { case leading, trailing }
    let notch: Notch
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        let card = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let x = notch == .leading ? rect.minX : rect.maxX
        var notches = Path()
        notches.addEllipse(in: CGRect(x: x - notchRadius, y: rect.minY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        notches.addEllipse(in: CGRect(x: x - notchRadius, y: rect.maxY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        return card.subtracting(notches)
    }
}

/// A home-screen-style icon from the bundled logo art. The logos ship with
/// white corners, so they're filled and clipped rather than padded.
struct OnboardingAppIcon: View {
    let asset: String
    let size: CGFloat

    var body: some View {
        Image(asset)
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
            .scaleEffect(1.08)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// A padlock drawn in two parts so the shackle can spring open.
struct OnboardingPadlock: View {
    let isOpen: Bool
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            OnboardingShackleShape()
                .stroke(
                    LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)
                )
                .frame(width: size * 0.54, height: size * 0.5)
                .offset(y: -size * 0.3 - (isOpen ? size * 0.16 : 0))
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: UnitPoint(x: 0.3, y: 0.5))

            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(LinearGradient(colors: [OB.amber, Color(red: 0.93, green: 0.56, blue: 0.13)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    VStack(spacing: -size * 0.02) {
                        Circle().frame(width: size * 0.16, height: size * 0.16)
                        RoundedRectangle(cornerRadius: 2).frame(width: size * 0.07, height: size * 0.14)
                    }
                    .foregroundStyle(Color.black.opacity(0.45))
                )
                .frame(width: size * 0.82, height: size * 0.62)
                .offset(y: size * 0.12)
        }
        .frame(width: size, height: size * 1.1)
        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
    }
}

struct OnboardingShackleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct OnboardingShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = sin(travel * .pi * 4) * 0.22
        let transform = CGAffineTransform(translationX: size.width / 2, y: size.height)
            .rotated(by: angle)
            .translatedBy(x: -size.width / 2, y: -size.height)
        return ProjectionTransform(transform)
    }
}

/// A short radial burst of sparks for payoff moments.
struct OnboardingSparkBurst: View {
    let active: Bool
    let radius: CGFloat
    private let count = 12

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let angle = Double(index) / Double(count) * 2 * .pi
                let color: Color = [OB.success, OB.accent, OB.amber][index % 3]
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: index.isMultiple(of: 2) ? 14 : 9)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .offset(
                        x: cos(angle) * (active ? radius : radius * 0.25),
                        y: sin(angle) * (active ? radius : radius * 0.25)
                    )
                    .opacity(active ? 0 : 1)
                    .animation(.easeOut(duration: 0.8), value: active)
            }
        }
        .opacity(active ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Leaderboard climb

/// The user's card enters below real players from this week's Visual Memory
/// board and climbs past each one it beats — a tick of haptics and a rank
/// counter per pass — until it lands where the score would place. Every
/// name, level and rank comes from Game Center; without it the board stays
/// locked instead of being invented.
struct OnboardingLeaderboardClimb: View {
    let board: OnboardingBoardState
    let level: Int
    let compact: Bool
    let onPlayAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var userSlot: Int?
    @State private var landed = false
    @State private var climb: Task<Void, Never>?

    private var rowHeight: CGFloat { compact ? 48 : 56 }

    /// Rows shown around the landing spot, plus where the user lands.
    private struct Window {
        let rows: [LeaderboardEntryData]
        let firstRank: Int
        let landingSlot: Int
        let placement: Int?
        let above: LeaderboardEntryData?
        let cutoff: Int?
    }

    private var window: Window? {
        guard case .loaded(let entries, let totalPlayers) = board, level > 0 else { return nil }
        let beatenIndex = entries.firstIndex { $0.score < level } ?? entries.count
        // Only claim a rank that the loaded slice of the board can prove.
        let placementKnown = beatenIndex < entries.count || totalPlayers <= entries.count
        if placementKnown {
            // One player above the landing spot and up to four below, so the
            // climb passes several real players before it settles.
            let start = max(0, beatenIndex - 1)
            let end = min(entries.count, beatenIndex + (compact ? 3 : 4))
            let rows = Array(entries[start..<end])
            return Window(
                rows: rows,
                firstRank: start + 1,
                landingSlot: beatenIndex - start,
                placement: beatenIndex + 1,
                above: beatenIndex > 0 ? entries[beatenIndex - 1] : nil,
                cutoff: nil
            )
        }
        let rows = Array(entries.suffix(3))
        return Window(
            rows: rows,
            firstRank: entries.count - rows.count + 1,
            landingSlot: rows.count,
            placement: nil,
            above: entries.last,
            cutoff: entries.last?.score
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, compact ? 16 : 24)

            boardCard

            Spacer(minLength: 8)

            if level == 0 {
                Button(action: onPlayAgain) {
                    Label("Play again", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear(perform: startClimbIfReady)
        .onChange(of: boardKey) { startClimbIfReady() }
        .onDisappear { climb?.cancel() }
    }

    private var boardKey: String {
        switch board {
        case .loading: return "loading"
        case .unavailable: return "unavailable"
        case .loaded(let entries, _): return "loaded-\(entries.count)"
        }
    }

    // MARK: Header

    private var header: some View {
        let mascotSize: CGFloat = compact ? 84 : 120
        return VStack(spacing: compact ? 4 : 8) {
            ZStack {
                if landed, let placement = window?.placement, placement <= 3 {
                    Image("mascot-crown")
                        .resizable()
                        .scaledToFit()
                        .transition(.scale.combined(with: .opacity))
                } else if landed || level == 0 || !isLoaded {
                    RiveMascotView(mood: level == 0 ? .neutral : .happy, size: mascotSize, playbackPolicy: .continuous)
                } else {
                    Image("mascot-lookout")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: mascotSize, height: mascotSize)
            .scaleEffect(landed ? 1 : 0.92)
            .accessibilityHidden(true)

            Text(headline)
                .font(.brand(size: compact ? 28 : 36, weight: .heavy))
                .foregroundStyle(OB.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            Text(subline)
                .font(.system(size: compact ? 14 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(landed && percentileText != nil ? OB.success : OB.fg2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: landed)
        .animation(.easeOut(duration: 0.2), value: userSlot)
    }

    private var isLoaded: Bool {
        if case .loaded = board { return true }
        return false
    }

    private var liveRank: Int? {
        guard let window, let userSlot else { return nil }
        return window.firstRank + userSlot
    }

    private var headline: String {
        if level == 0 { return "One level gets you on the board." }
        switch board {
        case .loading: return "Checking this week's board…"
        case .unavailable: return "See where you'd place."
        case .loaded(let entries, _):
            if entries.isEmpty { return "You'd be #1 this week." }
            guard let window else { return "Checking this week's board…" }
            if window.placement == nil { return landed ? "On the climb." : "Climbing…" }
            let rank = liveRank ?? (window.firstRank + window.rows.count)
            return "You'd place #\(rank)\(landed ? "." : "…")"
        }
    }

    private var percentileText: String? {
        guard case .loaded(_, let totalPlayers) = board,
              let placement = window?.placement,
              totalPlayers >= placement, totalPlayers > 1 else { return nil }
        let percent = max(1, Int((Double(placement) / Double(totalPlayers) * 100).rounded(.up)))
        guard percent <= 50 else { return nil }
        return "Top \(percent)% of Visual Memory players this week"
    }

    private var subline: String {
        if level == 0 { return "Clear level 1 and your score counts." }
        switch board {
        case .loading: return "Visual Memory · this week"
        case .unavailable: return "Sign in to Game Center to compare with this week's players."
        case .loaded(let entries, _):
            if entries.isEmpty { return "Nobody has posted a Visual Memory score yet." }
            guard landed else { return "Level \(level) · Visual Memory · this week" }
            if let cutoff = window?.cutoff { return "The top 50 starts at level \(cutoff) this week." }
            return percentileText ?? "Level \(level) on this week's Visual Memory board"
        }
    }

    // MARK: Board

    @ViewBuilder
    private var boardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if level == 0 {
                // Nothing to place yet, so don't tease a spot.
                userRow(rank: nil)
            } else {
            switch board {
            case .loading:
                ForEach(0..<4, id: \.self) { _ in skeletonRow }
                    .redacted(reason: .placeholder)
            case .unavailable:
                lockedBoard
            case .loaded(let entries, _):
                if entries.isEmpty || level == 0 {
                    userRow(rank: level == 0 ? nil : 1)
                } else if let window {
                    climbingRows(window)
                    if landed { hookLine(window) }
                }
            }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OB.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(OB.border, lineWidth: 1))
    }

    private func climbingRows(_ window: Window) -> some View {
        let slot = userSlot ?? window.rows.count
        let count = window.rows.count + 1
        return ZStack(alignment: .top) {
            ForEach(Array(window.rows.enumerated()), id: \.element.id) { index, entry in
                playerRow(entry, passed: index >= slot)
                    .frame(height: rowHeight)
                    .offset(y: CGFloat(index >= slot ? index + 1 : index) * rowHeight)
            }
            userRow(rank: window.placement == nil ? nil : (liveRank ?? (window.firstRank + slot)))
                .frame(height: rowHeight)
                .offset(y: CGFloat(slot) * rowHeight)
                .zIndex(10)
        }
        .frame(height: CGFloat(count) * rowHeight, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: userSlot)
    }

    private func playerRow(_ entry: LeaderboardEntryData, passed: Bool) -> some View {
        let hues: [Color] = [OB.memoPurple, OB.coral, OB.amber, OB.success, Color(red: 0.35, green: 0.75, blue: 0.95)]
        let hue = hues[entry.username.unicodeScalars.reduce(0) { $0 + Int($1.value) } % hues.count]
        return HStack(spacing: 12) {
            // Once the user passes a player, that player drops one spot.
            rankBadge(passed ? entry.rank + 1 : entry.rank, highlighted: false)
                .contentTransition(.numericText())
            Text(String(entry.username.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(hue)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hue.opacity(0.18)))
            Text(entry.username)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OB.fg)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Lv \(entry.score)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(OB.fg2)
        }
        .padding(.horizontal, 10)
        .opacity(passed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private func userRow(rank: Int?) -> some View {
        HStack(spacing: 12) {
            if let rank {
                rankBadge(rank, highlighted: true)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 28)
            }
            Image("app-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            Text("You")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text("Lv \(level)")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight - 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OB.accent)
                .shadow(color: OB.accent.opacity(landed ? 0.7 : 0.35), radius: landed ? 18 : 10)
        )
        .scaleEffect(landed ? 1.03 : 1)
        .accessibilityElement(children: .combine)
    }

    private func rankBadge(_ rank: Int, highlighted: Bool) -> some View {
        let medal: Color? = rank == 1 ? OB.amber : rank == 2 ? Color(white: 0.78) : rank == 3 ? Color(red: 0.80, green: 0.52, blue: 0.32) : nil
        return Text("#\(rank)")
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundStyle(highlighted ? .white : (medal.map { _ in OB.bg } ?? OB.fg2))
            .frame(width: 40, height: 26)
            .background(
                Capsule().fill(highlighted ? Color.white.opacity(0.2) : (medal ?? Color.white.opacity(0.06)))
            )
    }

    private func hookLine(_ window: Window) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(OB.coral)
            Group {
                if let cutoff = window.cutoff {
                    Text("Reach level \(cutoff + 1) to crack the top 50.")
                } else if let above = window.above {
                    Text("Reach level \(above.score + 1) to pass \(above.username).")
                } else {
                    Text("Nobody's above you. Now defend it.")
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(OB.fg)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .padding(.horizontal, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.08)).frame(width: 40, height: 24)
            Circle().fill(Color.white.opacity(0.08)).frame(width: 32, height: 32)
            Capsule().fill(Color.white.opacity(0.08)).frame(width: 110, height: 12)
            Spacer()
            Capsule().fill(Color.white.opacity(0.08)).frame(width: 42, height: 12)
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 10)
    }

    private var lockedBoard: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in skeletonRow }
            }
            .blur(radius: 5)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(OB.accent))
                    .shadow(color: OB.accent.opacity(0.5), radius: 14)
                Text("Your spot is waiting")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg)
                Text("Level \(level) · sign in to Game Center to reveal it")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Climb

    private func startClimbIfReady() {
        guard climb == nil else { return }
        guard case .loaded(let entries, _) = board else {
            if case .unavailable = board { landed = true }
            return
        }
        guard let window, !entries.isEmpty else {
            withAnimation { landed = true }
            if level > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return
        }
        if reduceMotion {
            userSlot = window.landingSlot
            landed = true
            return
        }
        userSlot = window.rows.count
        climb = Task { @MainActor in
            let tick = UIImpactFeedbackGenerator(style: .rigid)
            tick.prepare()
            try? await Task.sleep(for: .milliseconds(500))
            var slot = window.rows.count
            var step = 0
            while slot > window.landingSlot {
                guard !Task.isCancelled else { return }
                slot -= 1
                step += 1
                userSlot = slot
                tick.impactOccurred(intensity: min(1, 0.55 + Double(step) * 0.15))
                SoundService.shared.playReelTick()
                try? await Task.sleep(for: .milliseconds(max(170, 330 - step * 40)))
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { landed = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if (window.placement ?? 99) <= 3 {
                SoundService.shared.playJackpotSting()
            } else {
                SoundService.shared.playComplete()
            }
        }
    }
}

/// The same reel and landing state used by the blocked-app unlock flow.
struct OnboardingRealSlotPage: View {
    let onContinue: () -> Void
    @State private var hasLanded = false

    var body: some View {
        GeometryReader { proxy in
            let machineHeight = min(492, proxy.size.height * 0.74)
            let machineScale = machineHeight / 560

            VStack(alignment: .leading, spacing: 0) {
                OBEyebrow(text: "MEMO'S BOOTH · PREVIEW")
                    .padding(.top, 12)

                Text("Spin for your pass.")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(OB.fg)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                Text("When a blocked app calls, Memo picks the game.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .padding(.top, 5)

                Spacer(minLength: 0)

                FocusUnlockSlotMachine(
                    mode: .demo,
                    onLanded: { _ in
                        withAnimation(.easeOut(duration: 0.25)) { hasLanded = true }
                    }
                )
                .frame(width: 360, height: 560)
                .scaleEffect(machineScale)
                .frame(maxWidth: .infinity)
                .frame(height: machineHeight)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .background(FocusSlotAtmosphere())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if hasLanded {
                    OBContinueButton(title: "Play Visual Memory", action: onContinue)
                } else {
                    Color.clear.frame(height: 54)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(OB.bg)
        }
        .preferredColorScheme(.dark)
    }
}

/// One optional round inside the production Visual Memory game view.
struct OnboardingVisualMemoryPage: View {
    let onContinue: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completedRound = false

    init(previewCompleted: Bool = false, onContinue: @escaping (Bool) -> Void) {
        self.onContinue = onContinue
        _completedRound = State(initialValue: previewCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if completedRound {
                rewardContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                gameContent
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: completedRound)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if completedRound {
                OBContinueButton(title: "Continue") { onContinue(true) }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(OB.bg)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var gameContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                OBEyebrow(text: "VISUAL MEMORY")
                Spacer()
                Button("Skip demo") { onContinue(false) }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Text("Finish a game. Earn 10 minutes.")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(OB.fg)
                .padding(.horizontal, 24)
                .padding(.top, 7)

            Text("Try one preview round below.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg3)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            VisualMemoryView(
                autoStart: true,
                isOnboardingPreview: true,
                onPreviewComplete: {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    completedRound = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rewardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You finished the preview.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(OB.fg)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)

            Text("A full game in Memo earns a 10-minute pass for a blocked app.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text("MEMO PASS · PREVIEW")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(alignment: .center) {
                    Text("10:00")
                        .font(.system(size: 80, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .tracking(-3)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    Image("logo-tiktok")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                }
                .padding(.top, 12)

                Text("Finish a full game to unlock for real.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [OB.accent, OB.memoPurple.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .rotationEffect(.degrees(-2))
            .shadow(color: OB.accent.opacity(0.3), radius: 28, y: 16)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 7) {
                Text("And your score can climb.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg)
                Text("Full games count toward the weekly Visual Memory leaderboard.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("VISUAL MEMORY")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Text("WEEKLY BOARD")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(OB.accent)
                .padding(.top, 12)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(OB.accent).frame(width: 85, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(OB.memoPurple.opacity(0.8)).frame(width: 55, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(OB.fg.opacity(0.16)).frame(width: 31, height: 8)
                    Spacer()
                    Text("Your next score →")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                }
            }
            .padding(18)
            .background(OB.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(OB.border, lineWidth: 1))

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }
}

/// Previews the production Focus Mode card's unlocked state without touching Screen Time.
struct OnboardingUnlockedFocusPage: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OBEyebrow(text: "AFTER THE GAME")
                .padding(.top, 26)

            Text("The pass you play for.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(-1)
                .foregroundStyle(OB.fg)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text("Finish a game. TikTok opens for 10 minutes, then Memo blocks it again.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .lineSpacing(3)
                .padding(.top, 12)

            Spacer(minLength: 28)

            FocusModeCard(previewUnlockMinutes: 10)

            Text("PREVIEW OF YOUR FOCUS MODE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(OB.fg3)
                .padding(.top, 12)

            Spacer(minLength: 28)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OBContinueButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(OB.bg)
        }
        .preferredColorScheme(.dark)
    }
}

enum OnboardingTrapApp: String, CaseIterable, Identifiable, Hashable {
    case tiktok
    case youtube
    case instagram
    case snapchat
    case x
    case reddit

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .tiktok: return 0
        case .youtube: return 1
        case .instagram: return 2
        case .snapchat: return 3
        case .x: return 4
        case .reddit: return 5
        }
    }

    var displayName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .snapchat: return "Snapchat"
        case .x: return "X"
        case .reddit: return "Reddit"
        }
    }

    var assetName: String {
        switch self {
        case .tiktok: return "logo-tiktok"
        case .youtube: return "logo-youtube"
        case .instagram: return "logo-instagram"
        case .snapchat: return "logo-snapchat"
        case .x: return "logo-x"
        case .reddit: return "logo-reddit"
        }
    }

    var tileTint: Color {
        switch self {
        case .tiktok: return OB.memoPurple
        case .youtube: return OB.coral
        case .instagram: return OB.memoPurple
        case .snapchat: return OB.amber
        case .x: return OB.fg
        case .reddit: return OB.coral
        }
    }
}

struct OnboardingTrapSelectionView: View {
    @Binding var selectedApps: Set<OnboardingTrapApp>
    let onContinue: () -> Void

    private let maxSelections = 3
    private var apps: [OnboardingTrapApp] { OnboardingTrapApp.allCases.sorted { $0.sortOrder < $1.sortOrder } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 18)

                VStack(alignment: .leading, spacing: 11) {
                    OBEyebrow(text: "YOUR FIRST GUARDRAIL")
                    Text("Which apps\nneed a pause?")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Choose up to three apps for your preview.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)

                previewNotice
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                targetList
                    .padding(.horizontal, 24)
                    .padding(.bottom, 132)
            }
            .responsiveContent(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                OBContinueButton(title: "Continue", action: onContinue)
                    .disabled(selectedApps.isEmpty)
                    .opacity(selectedApps.isEmpty ? 0.42 : 1)

                Text(selectedApps.isEmpty ? "Pick at least one preview target" : "Preview targets \(selectedApps.count)/\(maxSelections)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 20)
            .background(
                LinearGradient(
                    colors: [OB.bg.opacity(0), OB.bg.opacity(0.96), OB.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .preferredColorScheme(.dark)
    }

    private var previewNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OB.fg2)
                .frame(width: 20, height: 20)

            Text("Preview only · confirm real app access with Apple after purchase.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(OB.fg3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetList: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(apps) { app in
                trapTile(app)
            }
        }
    }

    private func trapTile(_ app: OnboardingTrapApp) -> some View {
        let isSelected = selectedApps.contains(app)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                if isSelected {
                    selectedApps.remove(app)
                } else if selectedApps.count < maxSelections {
                    selectedApps.insert(app)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(app.assetName)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(app == .x ? Color.white.opacity(0.92) : Color.white.opacity(0.08))
                        )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? OB.accent : OB.fg3)
                }

                Text(app.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? OB.accent.opacity(0.12) : OB.surface.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? OB.accent.opacity(0.72) : Color.white.opacity(0.09), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityHint(isSelected ? "Remove from preview" : "Add to preview, up to three apps")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct OnboardingConciseGoalsView: View {
    let selectedGoal: UserFocusGoal?
    let onSelect: (UserFocusGoal) -> Void
    let onContinue: () -> Void

    private let goals: [UserFocusGoal] = [.doomscrolling, .attentionShot, .screenTimeFrying]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 26)

            OBEyebrow(text: "YOUR FOCUS PLAN")
                .padding(.bottom, 12)

            Text("What would you\nlike back?")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(OB.fg)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Text("Pick the one thing Memo should help with first.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(OB.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            VStack(spacing: 10) {
                ForEach(goals) { goal in
                    goalRow(goal)
                }
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                OBContinueButton(title: "Continue", action: onContinue)
                    .disabled(selectedGoal == nil)
                    .opacity(selectedGoal == nil ? 0.45 : 1)
                Text("One quick choice. You can change this later.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(OB.bg)
        }
        .preferredColorScheme(.dark)
    }

    private func goalRow(_ goal: UserFocusGoal) -> some View {
        let selected = selectedGoal == goal
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                onSelect(goal)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: goal.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? OB.accent : OB.fg2)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text(goalLabel(goal))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? OB.accent : OB.fg3)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? OB.accent.opacity(0.11) : OB.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? OB.accent.opacity(0.74) : OB.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func goalLabel(_ goal: UserFocusGoal) -> String {
        switch goal {
        case .doomscrolling: return "Scroll less"
        case .attentionShot: return "Stay focused"
        case .screenTimeFrying: return "Get my time back"
        case .loseFocus: return "Stay focused"
        case .forgetInstantly: return "Remember more"
        case .getSharper: return "Stay mentally sharp"
        }
    }
}

// MARK: 5 · Trial reminder

/// Lets the user pick when they hear from us before the trial bills. The
/// dates on the calendar tiles come from the real StoreKit trial length, and
/// the banner is the exact notification that gets scheduled.
struct OnboardingTrialReminderView: View {
    let trialLabel: String?
    let trialDays: Int?
    @Binding var selectedDaysBefore: Int
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var switchSpace
    @State private var bannerShown = false
    @State private var bannerDrop = 0
    @State private var appeared = false

    private var trialEndDate: Date? {
        guard let trialDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: trialDays, to: .now)
    }

    private func reminderDate(daysBefore: Int) -> Date? {
        guard let trialEndDate,
              let date = Calendar.current.date(byAdding: .day, value: -daysBefore, to: trialEndDate),
              date > .now else { return nil }
        return date
    }

    private func select(_ days: Int) {
        guard selectedDaysBefore != days else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)) {
            selectedDaysBefore = days
        }
        dropBanner()
    }

    /// The banner slides away and drops back in with the new copy, the way a
    /// real notification lands.
    private func dropBanner() {
        guard !reduceMotion else { return }
        withAnimation(.easeIn(duration: 0.14)) { bannerShown = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            bannerDrop += 1
            withAnimation(.spring(response: 0.46, dampingFraction: 0.68)) { bannerShown = true }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) {
                notificationBanner(compact: compact)
                    .id(bannerDrop)
                    .offset(y: bannerShown ? 0 : -36)
                    .opacity(bannerShown ? 1 : 0)
                    .scaleEffect(bannerShown ? 1 : 0.94, anchor: .top)
                    .padding(.top, compact ? 0 : 8)

                Spacer(minLength: compact ? 10 : 20)

                RiveMascotView(mood: .happy, size: compact ? 104 : 150, playbackPolicy: .continuous)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(spacing: compact ? 6 : 10) {
                    OBHeadline(
                        text: "We'll remind you before your trial ends.",
                        size: compact ? 26 : 32,
                        alignment: .center
                    )
                    OBBodyText(text: "Pick when you want the heads-up.", size: compact ? 15 : 16, alignment: .center)
                }
                .padding(.top, compact ? 4 : 10)

                reminderSwitch(compact: compact)
                    .padding(.top, compact ? 18 : 28)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OBLayout.gutter)
            .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2)
            .frame(maxWidth: .infinity)
        }
        .obBottomBar {
            OBActionBar(
                title: "Continue",
                reassurance: "No payment due now",
                footnote: "We'll ask to send notifications after your trial starts.",
                backdrop: .clear,
                action: onContinue
            )
        }
        // Glow sits behind the pinned bar too, so it never ends in a seam.
        .background(alignment: .top) {
            Circle()
                .fill(OB.accent.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: 120)
                .allowsHitTesting(false)
        }
        .background(OB.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
                bannerShown = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { bannerShown = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    /// One capsule, two choices, a thumb that slides between them. The date
    /// lives in the banner above, so the choice itself stays simple.
    private func reminderSwitch(compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach([1, 2], id: \.self) { days in
                let isSelected = selectedDaysBefore == days
                Button { select(days) } label: {
                    Text("\(days) \(days == 1 ? "day" : "days") before")
                        .font(.system(size: compact ? 16 : 17, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : OB.fg2)
                        .frame(maxWidth: .infinity, minHeight: compact ? 50 : 56)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(OB.accent)
                                    .shadow(color: OB.accent.opacity(0.5), radius: 14, y: 6)
                                    .matchedGeometryEffect(id: "reminder-thumb", in: switchSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remind me \(days) \(days == 1 ? "day" : "days") before my trial ends")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(OB.surface))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func notificationBanner(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image("app-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(NotificationService.trialReminderTitle(daysBefore: selectedDaysBefore))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    Text(reminderDate(daysBefore: selectedDaysBefore).map {
                        $0.formatted(.dateTime.month(.abbreviated).day())
                    } ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(NotificationService.trialReminderBody)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 11 : 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification preview")
    }
}

// MARK: 4 · Free trial

/// "We want you to try Memo for free." One line, the mascot, lots of room.
/// No prices here — the paywall carries the full offer. Accounts without a
/// usable trial never see trial language.
struct OnboardingTrialOfferView: View {
    let hasTrial: Bool
    let isLoadingOffer: Bool
    let loadFailed: Bool
    let onRetry: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var glow = false

    private var title: String {
        if isLoadingOffer || loadFailed || hasTrial { return "We want you to try Memo for free." }
        return "Keep the feed locked."
    }

    private var detail: String {
        if loadFailed { return "Couldn't reach the App Store." }
        if isLoadingOffer || hasTrial { return "Full access. Every game, every block, every leaderboard." }
        return "Pick a plan on the next screen."
    }

    // Keyed so the pinned bar re-renders when the offer finishes loading.
    private var offerStateID: String { "\(isLoadingOffer)-\(loadFailed)-\(hasTrial)" }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < OBLayout.compactHeight
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(OB.accent.opacity(0.34))
                        .frame(width: compact ? 200 : 260, height: compact ? 200 : 260)
                        .blur(radius: 70)
                        .scaleEffect(glow ? 1.08 : 0.92)
                    Circle()
                        .fill(OB.memoPurple.opacity(0.22))
                        .frame(width: compact ? 140 : 180, height: compact ? 140 : 180)
                        .blur(radius: 50)
                        .offset(x: 50, y: 30)
                        .scaleEffect(glow ? 0.94 : 1.06)

                    RiveMascotView(mood: .happy, size: compact ? 170 : 230, playbackPolicy: .continuous)
                        .accessibilityHidden(true)
                }
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: compact ? 10 : 14) {
                    OBHeadline(text: title, size: compact ? 32 : 40, alignment: .center)
                    OBBodyText(text: detail, size: compact ? 15 : 17, alignment: .center)
                    if loadFailed {
                        Button("Try again", action: onRetry)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(OB.accent)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    } else if isLoadingOffer {
                        ProgressView().tint(OB.fg2).frame(height: 44)
                    }
                }
                .padding(.top, compact ? 12 : 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OBLayout.gutter)
            .frame(maxWidth: OBLayout.contentMaxWidth + OBLayout.gutter * 2)
            .frame(maxWidth: .infinity)
        }
        .background(OB.bg.ignoresSafeArea())
        .obBottomBar {
            OBActionBar(
                title: isLoadingOffer ? "Checking offer…" : "Continue",
                isEnabled: !isLoadingOffer && !loadFailed,
                action: onContinue
            )
            .id(offerStateID)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.08)) { appeared = true }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }
}

struct OnboardingUnlockLoopDemoView: View {
    let blockedApps: Set<OnboardingTrapApp>
    let onStarted: () -> Void
    let onComplete: (_ attempts: Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = true
    @State private var didTrackStart = false
    @State private var firstSelectedTile: Int?
    @State private var demoAttempts = 0
    @State private var demoComplete = false

    private var sortedApps: [OnboardingTrapApp] {
        blockedApps.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var displayedApps: [OnboardingTrapApp] {
        let apps = sortedApps.isEmpty ? [.tiktok] : sortedApps
        return Array(apps.prefix(3))
    }

    private var appSummary: String {
        let names = displayedApps.map(\.displayName)
        guard let first = names.first else { return "TikTok" }
        if names.count == 1 { return first }
        return "\(first) + \(names.count - 1) targets"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 24)

                OBEyebrow(text: "THE MEMO LOOP")
                    .padding(.bottom, 12)

                Text("Finish a game.\nEarn your unlock.")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                Text("In a focus session, Memo blocks your chosen apps, serves a brain game, then gives you a temporary unlock.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)

                selectedTargetsCard

                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(OB.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .accessibilityHidden(true)

                memorySampleCard

                if demoComplete {
                    sampleReceipt
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.top, 14)
                }

                Spacer(minLength: 24)
            }
            .responsiveContent(maxWidth: 500)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                OBContinueButton(title: demoComplete ? "Continue" : "Finish the sample game") {
                    guard demoComplete else { return }
                    onComplete(demoAttempts)
                }
                .disabled(!demoComplete)
                .opacity(demoComplete ? 1 : 0.46)

                if !demoComplete {
                    Text("Tap the two matching tiles above")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(OB.fg3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 12)
            .background(OB.bg)
        }
        .preferredColorScheme(.dark)
    }

    private var selectedTargetsCard: some View {
        HStack(spacing: 12) {
            HStack(spacing: -7) {
                ForEach(Array(displayedApps.enumerated()), id: \.element.id) { _, app in
                    Image(app.assetName)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(6)
                        .background(OB.surface, in: Circle())
                        .overlay(Circle().stroke(OB.bg, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                OBEyebrow(text: "YOUR PREVIEW TARGETS", color: OB.fg3)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                Text(appSummary)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OB.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(OB.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OB.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var memorySampleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OBEyebrow(text: "SAMPLE MEMORY GAME")
                Spacer()
                Text(demoComplete ? "COMPLETE" : "1 ROUND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(demoComplete ? OB.success : OB.fg3)
            }

            Text(demoComplete ? "Nice. Your sample unlock is ready." : "Find the matching pair.")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(OB.fg)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    memoryTile(index)
                }
            }
        }
        .padding(15)
        .background(OB.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OB.border, lineWidth: 1))
    }

    private func memoryTile(_ index: Int) -> some View {
        let isSelected = firstSelectedTile == index || (demoComplete && (index == 1 || index == 3))
        let symbols = ["square.grid.2x2.fill", "circle.fill", "triangle.fill", "circle.fill"]
        return Button {
            selectMemoryTile(index)
        } label: {
            Image(systemName: symbols[index])
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? OB.accent : OB.fg2)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isSelected ? OB.accent.opacity(0.12) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? OB.accent.opacity(0.7) : OB.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(demoComplete)
        .accessibilityLabel("Memory tile \(index + 1)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var sampleReceipt: some View {
        HStack(spacing: 13) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(OB.success)
                .frame(width: 42, height: 42)
                .background(OB.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("SAMPLE UNLOCK RECEIPT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Color(red: 0.30, green: 0.31, blue: 0.36))
                Text("10-minute sample unlock")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.11, blue: 0.16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
            Text("EXAMPLE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.04, green: 0.38, blue: 0.30))
        }
        .padding(14)
        .background(Color(red: 0.91, green: 0.88, blue: 0.79), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func selectMemoryTile(_ index: Int) {
        guard !demoComplete else { return }
        if !didTrackStart {
            didTrackStart = true
            onStarted()
        }

        guard let firstSelectedTile else {
            self.firstSelectedTile = index
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        guard firstSelectedTile != index else { return }

        demoAttempts += 1
        if Set([firstSelectedTile, index]) == Set([1, 3]) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                demoComplete = true
                self.firstSelectedTile = nil
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: 0.16)) {
                self.firstSelectedTile = index
            }
        }
    }

    private var interceptionScene: some View {
        VStack(alignment: .leading, spacing: 15) {
            interceptHero
                .frame(height: 178)

            randomGameDraw

            VStack(spacing: 2) {
                Text("Complete the round. Get a short unlock.")
                    .foregroundStyle(OB.fg.opacity(0.92))
                Text("Then Memo guards it again.")
                    .foregroundStyle(OB.fg2)
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        }
        .frame(height: 342, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private var interceptHero: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                RadialGradient(
                    colors: [OB.accent.opacity(0.18), OB.memoPurple.opacity(0.08), .clear],
                    center: .leading,
                    startRadius: 12,
                    endRadius: 245
                )
                .frame(width: width * 1.08, height: 210)
                .offset(x: -54, y: -14)
                .accessibilityHidden(true)

                RadialGradient(
                    colors: [OB.coral.opacity(0.22), .clear],
                    center: .center,
                    startRadius: 5,
                    endRadius: 104
                )
                .frame(width: 178, height: 134)
                .offset(x: width - 176, y: 18)
                .accessibilityHidden(true)

                Image("memo-flashlight")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 282, height: 158)
                    .offset(x: -8, y: 10)
                    .shadow(color: OB.memoPurple.opacity(0.24), radius: 22, y: 12)
                    .accessibilityHidden(true)

                appInterceptCluster
                    .frame(width: 168, height: 128)
                    .offset(x: max(width - 172, 158), y: 16)
            }
            .frame(width: width, height: 178)
        }
    }

    private var appInterceptCluster: some View {
        ZStack(alignment: .topLeading) {
            Text(appSummary)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(OB.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .offset(x: 2, y: 0)

            ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, app in
                interceptedAppIcon(app, index: index)
            }
        }
    }

    private func interceptedAppIcon(_ app: OnboardingTrapApp, index: Int) -> some View {
        let offsets: [CGSize] = [
            CGSize(width: 78, height: 34),
            CGSize(width: 36, height: 76),
            CGSize(width: 86, height: 108)
        ]
        let rotations: [Double] = [-8, 5, 9]
        let sizes: [CGFloat] = [50, 48, 52]
        let safeIndex = min(index, offsets.count - 1)

        return Image(app.assetName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: sizes[safeIndex], height: sizes[safeIndex])
            .rotationEffect(.degrees(rotations[safeIndex]))
            .shadow(color: OB.coral.opacity(0.38), radius: 16, y: 8)
            .background(
                Circle()
                    .fill(OB.coral.opacity(0.11))
                    .frame(width: sizes[safeIndex] + 24, height: sizes[safeIndex] + 24)
                    .blur(radius: 8)
            )
            .offset(offsets[safeIndex])
            .zIndex(Double(index + 1))
            .accessibilityHidden(true)
    }

    private var randomGameDraw: some View {
        VStack(spacing: 8) {
            Text("One random brain game appears")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(OB.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: -2) {
                trainCoverPreview(title: "Memory", type: .visualMemory, tint: AppColors.indigo, scale: 0.70, rotation: -4, y: 7)
                trainCoverPreview(title: "Speed", type: .colorMatch, tint: AppColors.sky, scale: 0.76, rotation: 0, y: 0)
                    .zIndex(2)
                trainCoverPreview(title: "Reaction", type: .reactionTime, tint: AppColors.coral, scale: 0.70, rotation: 4, y: 7)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func trainCoverPreview(
        title: String,
        type: ExerciseType,
        tint: Color,
        scale: CGFloat,
        rotation: Double,
        y: CGFloat
    ) -> some View {
        TrainGameCard(game: UnlockGame(exerciseType: type) ?? .visualMemory, lastPlayedText: nil)
        .frame(width: 140)
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .offset(y: y)
        .frame(width: 96, height: 108)
        .accessibilityElement(children: .combine)
    }

    private func start() {
        guard !didTrackStart else { return }
        didTrackStart = true
        onStarted()
        let animation: Animation = reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.48, dampingFraction: 0.84)
        withAnimation(animation.delay(0.06)) {
            appeared = true
        }
    }
}


struct OnboardingLifetimeProjection: Equatable {
    let age: Int
    let dailyScreenTimeHours: Double
    let projectionAge: Int = 80

    var clampedAge: Int {
        min(max(age, 1), projectionAge)
    }

    var remainingYears: Double {
        Double(max(projectionAge - clampedAge, 1))
    }

    var sleepYears: Double {
        remainingYears * 8.0 / 24.0
    }

    var workSchoolYears: Double {
        let yearsUntilWorkEnds = Double(max(min(65 - clampedAge, projectionAge - clampedAge), 0))
        return yearsUntilWorkEnds * (50.0 / 168.0)
    }

    var phoneYears: Double {
        remainingYears * min(max(dailyScreenTimeHours, 0), 16) / 24.0
    }

    var flexibleYearsBeforePhone: Double {
        max(remainingYears - sleepYears - workSchoolYears, 0.1)
    }

    var phoneShareOfFreeYears: Int {
        min(99, max(1, Int((phoneYears / flexibleYearsBeforePhone * 100).rounded())))
    }

    var freeYearsBeforePhoneText: String {
        formatYearNumber(flexibleYearsBeforePhone)
    }

    var phoneYearsText: String {
        formatYearAmount(min(phoneYears, flexibleYearsBeforePhone))
    }

    var finalQuestion: String {
        let phoneCost = phoneYears >= flexibleYearsBeforePhone
            ? "all of them (\(phoneShareOfFreeYears)%)"
            : "\(phoneYearsText) of them (\(phoneShareOfFreeYears)%)"
        return "You have about \(freeYearsBeforePhoneText) free years left. At this pace, your phone takes \(phoneCost). Do you really want that?"
    }

    func formatYearAmount(_ years: Double) -> String {
        if years < 0.5 { return "less than 1 year" }
        let rounded = (years * 10).rounded() / 10
        if rounded == 1 { return "1 year" }
        return "\(formatYearNumber(years)) years"
    }

    private func formatYearNumber(_ years: Double) -> String {
        String(format: "%.1f", years)
    }
}

enum OnboardingLifeReceiptBeat: Int, CaseIterable {
    case allLife = 0
    case yearsAhead
    case sleepLocked
    case workSchoolLocked
    case yourTime
    case phoneTakeover
    case phoneTruth
    case rescue
}

enum OnboardingLifeReceiptSquareRole: Equatable {
    case life
    case lived
    case future
    case sleep
    case workSchool
    case yourTime
    case phone
    case protectedPhone
}

struct OnboardingLifeReceiptSquareModel: Equatable {
    let projection: OnboardingLifetimeProjection

    var totalYearsCount: Int { projection.projectionAge }
    var livedCount: Int { min(projection.clampedAge, totalYearsCount - 1) }
    var yearsAheadCount: Int { max(totalYearsCount - livedCount, 1) }
    var sleepCount: Int { clampedCount(projection.sleepYears, available: yearsAheadCount) }
    var workSchoolCount: Int {
        clampedCount(projection.workSchoolYears, available: yearsAheadCount - sleepCount)
    }
    var yourTimeBeforePhoneCount: Int {
        max(yearsAheadCount - sleepCount - workSchoolCount, 1)
    }
    var phoneCount: Int {
        clampedCount(projection.phoneYears, available: yourTimeBeforePhoneCount)
    }
    var yourTimeAfterPhoneCount: Int {
        max(yourTimeBeforePhoneCount - phoneCount, 0)
    }
    var protectedPhoneCount: Int {
        min(phoneCount, max(3, Int((Double(phoneCount) * 0.56).rounded())))
    }
    var remainingPhoneCountAfterProtection: Int {
        max(phoneCount - protectedPhoneCount, 0)
    }

    var yearsAhead: Double { projection.remainingYears }
    var sleepYears: Double { projection.sleepYears }
    var workSchoolYears: Double { projection.workSchoolYears }
    var freeYears: Double { projection.flexibleYearsBeforePhone }
    var phoneYears: Double { projection.phoneYears }

    var finalCostRoles: [OnboardingLifeReceiptSquareRole] {
        repeated(.lived, livedCount)
        + repeated(.sleep, sleepCount)
        + repeated(.workSchool, workSchoolCount)
        + repeated(.yourTime, yourTimeAfterPhoneCount)
        + repeated(.phone, phoneCount)
    }

    func viewportRoles(for beat: OnboardingLifeReceiptBeat) -> [OnboardingLifeReceiptSquareRole] {
        switch beat {
        case .allLife:
            return repeated(.life, totalYearsCount)
        case .yearsAhead:
            return repeated(.future, yearsAheadCount)
        case .sleepLocked:
            return repeated(.sleep, sleepCount)
            + repeated(.future, max(yearsAheadCount - sleepCount, 0))
        case .workSchoolLocked:
            return repeated(.workSchool, workSchoolCount)
            + repeated(.future, yourTimeBeforePhoneCount)
        case .yourTime:
            return repeated(.yourTime, yourTimeBeforePhoneCount)
        case .phoneTakeover, .phoneTruth:
            return repeated(.yourTime, yourTimeAfterPhoneCount)
            + repeated(.phone, phoneCount)
        case .rescue:
            return repeated(.yourTime, yourTimeAfterPhoneCount)
            + repeated(.phone, remainingPhoneCountAfterProtection)
            + repeated(.protectedPhone, protectedPhoneCount)
        }
    }

    func roles(for beat: OnboardingLifeReceiptBeat) -> [OnboardingLifeReceiptSquareRole] {
        switch beat {
        case .allLife:
            return repeated(.life, totalYearsCount)
        case .yearsAhead:
            return repeated(.lived, livedCount)
            + repeated(.future, yearsAheadCount)
        case .sleepLocked:
            return repeated(.lived, livedCount)
            + repeated(.sleep, sleepCount)
            + repeated(.future, max(yearsAheadCount - sleepCount, 0))
        case .workSchoolLocked:
            return repeated(.lived, livedCount)
            + repeated(.sleep, sleepCount)
            + repeated(.workSchool, workSchoolCount)
            + repeated(.future, max(yearsAheadCount - sleepCount - workSchoolCount, 0))
        case .yourTime:
            return repeated(.lived, livedCount)
            + repeated(.sleep, sleepCount)
            + repeated(.workSchool, workSchoolCount)
            + repeated(.yourTime, yourTimeBeforePhoneCount)
        case .phoneTakeover, .phoneTruth:
            return repeated(.lived, livedCount)
            + repeated(.sleep, sleepCount)
            + repeated(.workSchool, workSchoolCount)
            + repeated(.yourTime, yourTimeAfterPhoneCount)
            + repeated(.phone, phoneCount)
        case .rescue:
            return repeated(.lived, livedCount)
            + repeated(.sleep, sleepCount)
            + repeated(.workSchool, workSchoolCount)
            + repeated(.yourTime, yourTimeAfterPhoneCount)
            + repeated(.phone, remainingPhoneCountAfterProtection)
            + repeated(.protectedPhone, protectedPhoneCount)
        }
    }

    private func clampedCount(_ years: Double, available: Int) -> Int {
        min(max(Int(years.rounded()), 0), max(available, 0))
    }

    private func repeated(
        _ role: OnboardingLifeReceiptSquareRole,
        _ count: Int
    ) -> [OnboardingLifeReceiptSquareRole] {
        Array(repeating: role, count: max(count, 0))
    }
}

enum OnboardingLifeReceiptProgress {
    static let finalStage = OnboardingLifeReceiptBeat.rescue.rawValue

    static func canContinue(stage: Int, receiptFinished: Bool) -> Bool {
        stage >= finalStage && receiptFinished
    }
}

private struct LifeReceiptGridCamera {
    let scale: CGFloat
    let anchor: UnitPoint
    let offset: CGSize

    static let identity = LifeReceiptGridCamera(scale: 1, anchor: .center, offset: .zero)
}

struct OnboardingLifetimeShockView: View {
    let age: Int
    let dailyScreenTimeHours: Double
    let isEstimate: Bool
    let isLoadingScreenTime: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealStarted = false
    @State private var numberVisible = false
    @State private var oofVisible = false
    @State private var glowPulse = false
    @State private var animatedPhoneYears: Double = 0
    @State private var countUpFinished = false
    @State private var proofVisible = false
    @State private var ctaVisible = false

    private var projection: OnboardingLifetimeProjection {
        OnboardingLifetimeProjection(age: age, dailyScreenTimeHours: dailyScreenTimeHours)
    }

    private var targetPhoneYears: Double {
        min(projection.phoneYears, projection.flexibleYearsBeforePhone)
    }

    private var displayedYearsText: String {
        if countUpFinished { return projection.phoneYearsText }
        return String(format: "%.1f years", animatedPhoneYears)
    }

    private var dailyHoursLabel: String {
        OnboardingScreenTimeHoursFormatter.dailyLabel(hours: dailyScreenTimeHours, isEstimate: isEstimate)
    }

    private var sourceText: String {
        if isLoadingScreenTime { return "reading your Screen Time" }
        return isEstimate ? "using your estimate - \(dailyHoursLabel)/day" : "from your Screen Time - \(dailyHoursLabel)/day"
    }

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()

            RadialGradient(
                colors: [OB.coral.opacity(0.28), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 330
            )
            .offset(y: -40)
            .ignoresSafeArea()

            // One-shot pulse layered over the base glow, fired on the
            // count-up landing thud. Never loops.
            RadialGradient(
                colors: [OB.coral.opacity(0.30), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 330
            )
            .offset(y: -40)
            .ignoresSafeArea()
            .opacity(glowPulse ? 0.65 : 0)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 18)

                Text(sourceText)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(isEstimate ? OB.fg3 : OB.accent.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 28)

                Spacer(minLength: 58)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Oof.")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundStyle(OB.coral)
                        .shadow(color: OB.coral.opacity(0.28), radius: 18, y: 8)
                        .scaleEffect(oofVisible ? 1 : 1.5, anchor: .bottomLeading)
                        .opacity(oofVisible ? 1 : 0)

                    Text("At \(dailyHoursLabel)/day, the feed is on track to take")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayedYearsText)
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(OB.coral)
                            .minimumScaleFactor(0.74)
                            .lineLimit(1)
                            .scaleEffect(numberVisible ? 1 : 0.92, anchor: .leading)
                            .opacity(numberVisible ? 1 : 0)
                        Text("of your life before age \(projection.projectionAge).")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(OB.fg)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(OB.accent)
                            .frame(width: 26)
                        Text(isEstimate ? "This is based on your estimate. Memo will use real Screen Time when it is connected." : "Calculated from your Screen Time. This stays on your phone.")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OB.fg2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(OB.surface.opacity(0.72))
                            .stroke(OB.accent.opacity(0.18), lineWidth: 1)
                    )
                    .opacity(proofVisible ? 1 : 0)
                    .offset(y: proofVisible ? 0 : 8)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 112)
            }
            .responsiveContent(maxWidth: 500)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OBContinueButton(title: "Show me where it goes", action: onContinue)
                .opacity(ctaVisible ? 1 : 0)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .padding(.top, 18)
                .background(
                    LinearGradient(
                        colors: [OB.bg.opacity(0), OB.bg.opacity(0.96), OB.bg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .preferredColorScheme(.dark)
        .onAppear { startReveal() }
    }

    private func startReveal() {
        guard !revealStarted else { return }
        revealStarted = true
        let target = targetPhoneYears

        // Tiny costs don't earn a count-up; reduce-motion always skips it.
        guard !reduceMotion, target >= 2 else {
            Task { @MainActor in
                animatedPhoneYears = target
                countUpFinished = true
                try? await Task.sleep(nanoseconds: nanoseconds(0.05))
                withAnimation(.linear(duration: 0.01)) {
                    numberVisible = true
                    oofVisible = true
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.90)
                try? await Task.sleep(nanoseconds: nanoseconds(0.05))
                withAnimation(.linear(duration: 0.01)) { proofVisible = true }
                try? await Task.sleep(nanoseconds: nanoseconds(0.05))
                withAnimation(.linear(duration: 0.01)) { ctaVisible = true }
            }
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds(0.25))
            withAnimation(.easeOut(duration: 0.20)) {
                numberVisible = true
            }

            // Count 0 → target with cubic ease-out; haptic ticks ramp up
            // and land on a heavy thud. Generators are held + prepared so
            // the Taptic Engine never fires cold.
            let steps = 24
            let tick = UIImpactFeedbackGenerator(style: .rigid)
            let thud = UIImpactFeedbackGenerator(style: .heavy)
            let stamp = UIImpactFeedbackGenerator(style: .medium)
            tick.prepare()
            thud.prepare()
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 3)
                animatedPhoneYears = target * eased
                if step % 3 == 0 && step < steps {
                    tick.impactOccurred(intensity: 0.60 + 0.40 * progress)
                    tick.prepare()
                }
                try? await Task.sleep(nanoseconds: nanoseconds(1.1 / Double(steps)))
            }
            animatedPhoneYears = target
            countUpFinished = true

            thud.impactOccurred()
            stamp.prepare()
            withAnimation(.spring(response: 0.50, dampingFraction: 0.60)) {
                glowPulse = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanoseconds(0.30))
                withAnimation(.easeOut(duration: 0.50)) { glowPulse = false }
            }

            try? await Task.sleep(nanoseconds: nanoseconds(0.25))
            withAnimation(.spring(response: 0.36, dampingFraction: 0.70)) {
                oofVisible = true
            }
            stamp.impactOccurred()

            try? await Task.sleep(nanoseconds: nanoseconds(0.40))
            withAnimation(.easeOut(duration: 0.38)) {
                proofVisible = true
            }
            try? await Task.sleep(nanoseconds: nanoseconds(0.35))
            withAnimation(.easeOut(duration: 0.34)) {
                ctaVisible = true
            }
        }
    }

    private func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0.01, seconds) * 1_000_000_000)
    }
}

struct OnboardingWillpowerProofView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headlineVisible = false
    @State private var rowsVisible = false
    @State private var ctaVisible = false

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()

            RadialGradient(
                colors: [OB.memoPurple.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 340
            )
            .offset(x: 80, y: -70)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 64)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Willpower loses to dopamine loops.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(-1)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Apps are built to pull you back. Memo changes what happens before the feed opens.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 10)
                .padding(.horizontal, 28)

                Spacer(minLength: 38)

                VStack(spacing: 12) {
                    proofRow(
                        icon: "sparkles",
                        title: "Feeds exploit variable rewards",
                        detail: "You keep checking because the next hit might be good.",
                        tint: OB.coral
                    )
                    proofRow(
                        icon: "lock.open.fill",
                        title: "Plain blockers create rebound",
                        detail: "The app opens again and the same habit is still waiting.",
                        tint: OB.fg3
                    )
                    proofRow(
                        icon: "brain.head.profile",
                        title: "Memo inserts training first",
                        detail: "Memory, attention, and speed reps become the gate back in.",
                        tint: OB.accent
                    )
                }
                .opacity(rowsVisible ? 1 : 0)
                .offset(y: rowsVisible ? 0 : 12)
                .padding(.horizontal, 24)

                Spacer(minLength: 112)
            }
            .responsiveContent(maxWidth: 500)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OBContinueButton(title: "Build my counterattack", action: onContinue)
                .opacity(ctaVisible ? 1 : 0)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .padding(.top, 18)
                .background(
                    LinearGradient(
                        colors: [OB.bg.opacity(0), OB.bg.opacity(0.96), OB.bg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .preferredColorScheme(.dark)
        .onAppear { startReveal() }
    }

    private func proofRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(OB.fg2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(OB.surface.opacity(0.70))
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }

    private func startReveal() {
        guard !headlineVisible else { return }
        Task { @MainActor in
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.38)) {
                headlineVisible = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.62)
            try? await Task.sleep(nanoseconds: nanoseconds(reduceMotion ? 0.05 : 0.52))
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.42)) {
                rowsVisible = true
            }
            try? await Task.sleep(nanoseconds: nanoseconds(reduceMotion ? 0.05 : 0.44))
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.34)) {
                ctaVisible = true
            }
        }
    }

    private func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0.01, seconds) * 1_000_000_000)
    }
}

struct OnboardingLifeSquaresReceiptView: View {
    let age: Int
    let dailyScreenTimeHours: Double
    let isEstimate: Bool
    let isLoadingScreenTime: Bool
    let sourceLine: String
    var previewBeat: OnboardingLifeReceiptBeat? = nil
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat: OnboardingLifeReceiptBeat = .allLife
    @State private var receiptFinished = false
    @State private var animationTask: Task<Void, Never>?
    @State private var activeDotIndex: Int?
    /// One-shot group pulse of the phone squares on the "That is X years." beat.
    @State private var truthPulse = false
    /// Highest roles-index the takeover sweep has consumed. Phone dots
    /// past this still render alive — the sweep turning them red one by one
    /// is the entire point of the beat.
    @State private var takenThroughIndex = Int.max
    /// Opening shot: camera starts tight on ~4 dots, then pulls back to
    /// reveal all 80 as the headline stamps in. The smallness of the grid IS
    /// the point — the pull-back makes you feel it.
    @State private var introRevealDone = false
    @State private var isAdvancingBeat = false
    @State private var receiptLineFinished = false
    /// Incremented by tapping the content area to finish the typewriter
    /// line instantly — impatient users control the pace, the CTA gate stays.
    @State private var typewriterSkipToken = 0

    private var projection: OnboardingLifetimeProjection {
        OnboardingLifetimeProjection(age: age, dailyScreenTimeHours: dailyScreenTimeHours)
    }

    private var squareModel: OnboardingLifeReceiptSquareModel {
        OnboardingLifeReceiptSquareModel(projection: projection)
    }

    private var phoneYears: Double {
        projection.phoneYears
    }

    private var headlineText: String {
        switch beat {
        case .allLife:
            return "This is your life."
        case .yearsAhead:
            return "You are here."
        case .sleepLocked:
            return "Sleep is spoken for."
        case .workSchoolLocked:
            return "Work and school take their share."
        case .yourTime:
            return "This is what's left for you."
        case .phoneTakeover:
            return "Your phone starts taking years."
        case .phoneTruth:
            return "That is \(projection.phoneYearsText)."
        case .rescue:
            return "Memo gets there before the feed."
        }
    }

    private var receiptLine: String {
        switch beat {
        case .allLife:
            return "Each dot is one year."
        case .yearsAhead:
            return "\(projection.projectionAge) - \(projection.clampedAge) = \(squareModel.yearsAheadCount) years still in front of you."
        case .sleepLocked:
            return "\(projection.formatYearAmount(squareModel.sleepYears)) disappear into sleep."
        case .workSchoolLocked:
            return "\(projection.formatYearAmount(squareModel.workSchoolYears)) more go to work and school."
        case .yourTime:
            return "After that, \(projection.freeYearsBeforePhoneText) flexible years are actually yours."
        case .phoneTakeover:
            return "Now watch the feed take them one by one."
        case .phoneTruth:
            return "At \(dailyHoursLabel)/day, the feed gets that from the years that were actually yours."
        case .rescue:
            return "Memo cannot give back the years already gone."
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            ZStack {
                lifetimeAtmosphere

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: compact ? 8 : 12)

                    sourceHeader
                        .padding(.horizontal, 28)

                    Spacer().frame(height: compact ? 18 : 26)

                    headlineBlock(compact: compact)
                        .padding(.horizontal, 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !receiptLineFinished else { return }
                            typewriterSkipToken += 1
                        }

                    Spacer(minLength: compact ? 16 : 26)

                    lifeGridSurface
                        .padding(.horizontal, 24)

                    Spacer(minLength: compact ? 20 : 32)

                    if beat == .rescue {
                        finalReceiptCallout
                            .padding(.horizontal, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: 104)
                }
                .responsiveContent(maxWidth: 500)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OBContinueButton(title: receiptCTATitle, action: handleReceiptCTA)
                .disabled(!canUseReceiptCTA)
                .opacity(canUseReceiptCTA ? 1 : 0)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .padding(.top, 18)
                .background(
                    LinearGradient(
                        colors: [OB.bg.opacity(0), OB.bg.opacity(0.96), OB.bg],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if applyPreviewBeatIfNeeded() {
                introRevealDone = true
                return
            }
            if isLoadingScreenTime {
                animationTask?.cancel()
                beat = .allLife
                receiptFinished = false
                receiptLineFinished = false
                isAdvancingBeat = false
                activeDotIndex = nil
            } else {
                resetReceiptForManualStepping()
            }
            startIntroReveal()
        }
        .onChange(of: isLoadingScreenTime) { _, isLoading in
            if applyPreviewBeatIfNeeded() {
                return
            }
            if isLoading {
                animationTask?.cancel()
                beat = .allLife
                receiptFinished = false
                receiptLineFinished = false
                isAdvancingBeat = false
                activeDotIndex = nil
            } else {
                resetReceiptForManualStepping()
            }
        }
        .onDisappear { animationTask?.cancel() }
    }

    private var canUseReceiptCTA: Bool {
        guard !isLoadingScreenTime, !isAdvancingBeat, receiptLineFinished else { return false }
        if beat == .rescue {
            return receiptFinished
        }
        return true
    }

    private var receiptCTATitle: String {
        switch beat {
        case .allLife:
            return "Subtract my age"
        case .yearsAhead:
            return "Take out sleep"
        case .sleepLocked:
            return "Take out work & school"
        case .workSchoolLocked:
            return "Show what is actually mine"
        case .yourTime, .phoneTakeover:
            return "Show what the feed takes"
        case .phoneTruth:
            return "I don't want to give the feed that"
        case .rescue:
            return "Show me the counterattack"
        }
    }

    private var lifetimeAtmosphere: some View {
        ZStack {
            OB.bg

            RadialGradient(
                colors: [
                    (isDamageFocus ? OB.coral : OB.accent).opacity(0.18),
                    OB.bg.opacity(0.02),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 360
            )
            .offset(x: 80, y: -70)

            RadialGradient(
                colors: [
                    OB.memoPurple.opacity(0.12),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 320
            )
            .offset(x: -76, y: 120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func headlineBlock(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(headlineText)
                .font(.system(size: compact ? 34 : 39, weight: .black, design: .rounded))
                .foregroundStyle(beat == .phoneTruth ? OB.fg : OB.fg)
                .lineSpacing(-1)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)
                // "This is your life." stamps in as the opening pull-back resolves.
                .scaleEffect(beat == .allLife && !introRevealDone ? 1.26 : 1, anchor: .bottomLeading)
                .opacity(beat == .allLife && !introRevealDone ? 0 : 1)

            if beat == .phoneTruth {
                Text("Not screen time. Years.")
                    .font(.system(size: compact ? 26 : 30, weight: .black, design: .rounded))
                    .foregroundStyle(OB.coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .shadow(color: OB.coral.opacity(0.26), radius: 16, y: 7)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }

            TypewriterText(
                fullText: isLoadingScreenTime ? "Reading your Screen Time..." : receiptLine,
                speed: reduceMotion ? 0.001 : 0.052,
                hapticEnabled: !reduceMotion,
                skipToken: typewriterSkipToken,
                onComplete: {
                    receiptLineFinished = true
                    if beat == .rescue {
                        receiptFinished = true
                    }
                }
            )
            .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .rounded))
            .foregroundStyle(copyColor)
            .lineSpacing(3)
            .frame(minHeight: compact ? 42 : 50, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: beat)
    }

    private var copyColor: Color {
        switch beat {
        case .phoneTruth:
            return OB.coral.opacity(0.86)
        case .rescue:
            return OB.accent.opacity(0.92)
        default:
            return OB.fg2
        }
    }

    private var lifeGridSurface: some View {
        squareCanvas
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.54, dampingFraction: 0.82), value: beat)
    }

    private var sourceHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 0)

            Text(sourceBadgeText)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(sourceBadgeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if isLoadingScreenTime {
                ProgressView()
                    .tint(OB.accent)
                    .scaleEffect(0.62)
            }
        }
    }

    private var sourceBadgeText: String {
        if isLoadingScreenTime { return "reading your Screen Time" }
        let source = isEstimate ? "using your estimate" : "from your Screen Time"
        return "\(source) - \(dailyHoursLabel)/day"
    }

    private var sourceBadgeColor: Color {
        if isDamageFocus { return OB.coral.opacity(0.92) }
        if beat == .rescue { return OB.accent.opacity(0.86) }
        return OB.fg3
    }

    private var squareCanvas: some View {
        VStack(spacing: shouldShowLegend ? 16 : 0) {
            let roles = squareModel.viewportRoles(for: beat)
            let camera = receiptCamera

            LazyVGrid(columns: gridColumns, spacing: squareSpacing) {
                    ForEach(Array(roles.enumerated()), id: \.offset) { index, role in
                        LifeReceiptSquare(
                            role: role,
                            isDamageFocus: isDamageFocus,
                            isRescueBeat: beat == .rescue,
                            isActive: activeDotIndex == index,
                            isPulsing: truthPulse && role == .phone,
                            isAwaitingTake: beat == .phoneTakeover && role == .phone && index > takenThroughIndex,
                            isBreathing: (beat == .allLife || beat == .yearsAhead) && introRevealDone,
                            breatheDelay: Double(index % 8) * 0.10 + Double(index / 8) * 0.05
                        )
                        .frame(width: dotSize, height: dotSize)
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                            .animation(
                                squareAnimation.delay(squareDelay(index: index, role: role, roles: roles)),
                                value: beat
                            )
                    }
                }
                .frame(maxWidth: gridMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(alignment: .bottomTrailing) {
                    if isDamageFocus {
                        LinearGradient(
                            colors: [
                                OB.coral.opacity(0.00),
                                OB.coral.opacity(0.18),
                                OB.coral.opacity(0.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 260, height: 96)
                        .blur(radius: 18)
                        .offset(x: 18, y: 18)
                        .transition(.opacity)
                    }
                }
                .scaleEffect(camera.scale, anchor: camera.anchor)
                .offset(x: camera.offset.width, y: camera.offset.height)
                .animation(receiptCameraAnimation, value: beat)

            if shouldShowLegend {
                gridLegend
                    .frame(maxWidth: gridMaxWidth)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .accessibilityLabel(accessibilityGridLabel)
        .frame(minHeight: 300, alignment: .center)
        .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.58, dampingFraction: 0.86), value: beat)
    }

    private var gridLegend: some View {
        HStack(spacing: 8) {
            ForEach(Array(legendItems.enumerated()), id: \.offset) { _, item in
                legendItem(role: item.role, label: item.label)
            }
        }
        .font(.system(size: 8.5, weight: .black, design: .monospaced))
        .tracking(0.5)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private var legendItems: [(role: OnboardingLifeReceiptSquareRole, label: String)] {
        switch beat {
        case .sleepLocked:
            return [(.sleep, "SLEEP"), (.future, "LEFT")]
        case .workSchoolLocked:
            return [(.workSchool, "WORK"), (.future, "LEFT")]
        case .yourTime:
            return [(.yourTime, "YOURS")]
        case .phoneTakeover, .phoneTruth:
            return [(.yourTime, "YOURS"), (.phone, "PHONE")]
        case .rescue:
            return [(.yourTime, "YOURS"), (.phone, "PHONE"), (.protectedPhone, "PROTECTED")]
        case .allLife, .yearsAhead:
            return []
        }
    }

    private func legendItem(role: OnboardingLifeReceiptSquareRole, label: String) -> some View {
        HStack(spacing: 4) {
            LifeReceiptSquare(
                role: role,
                isDamageFocus: false,
                isRescueBeat: beat == .rescue,
                isActive: false
            )
            .frame(width: 8, height: 8)

            Text(label)
                .foregroundStyle(legendColor(for: role))
        }
    }

    private func legendColor(for role: OnboardingLifeReceiptSquareRole) -> Color {
        switch role {
        case .phone:
            return OB.coral.opacity(0.88)
        case .protectedPhone, .lived:
            return OB.accent.opacity(0.90)
        case .future:
            return OB.accent.opacity(0.76)
        case .sleep:
            return OB.memoPurple.opacity(0.86)
        case .workSchool:
            return OB.fg3.opacity(0.90)
        default:
            return OB.fg2
        }
    }

    private var finalReceiptCallout: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("memo-flashlight")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .shadow(color: OB.accent.opacity(0.28), radius: 12, y: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("The next year is still yours.")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Train first. Then unlock.")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(OB.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isDamageFocus: Bool {
        beat == .phoneTakeover || beat == .phoneTruth
    }

    private var shouldShowLegend: Bool {
        beat.rawValue >= OnboardingLifeReceiptBeat.sleepLocked.rawValue
    }

    private var gridColumnCount: Int {
        8
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: squareSpacing), count: gridColumnCount)
    }

    private var squareSpacing: CGFloat {
        10
    }

    private var gridMaxWidth: CGFloat {
        292
    }

    private var dotSize: CGFloat {
        20
    }

    private var receiptCamera: LifeReceiptGridCamera {
        guard !reduceMotion else { return .identity }

        switch beat {
        case .allLife:
            // Opening shot: tight on a handful of dots, then pull back.
            return introRevealDone
                ? .identity
                : LifeReceiptGridCamera(scale: 3.2, anchor: .center, offset: .zero)
        case .yearsAhead:
            return LifeReceiptGridCamera(
                scale: 1.06,
                anchor: .center,
                offset: .zero
            )
        case .sleepLocked:
            return LifeReceiptGridCamera(
                scale: 1.09,
                anchor: .center,
                offset: .zero
            )
        case .workSchoolLocked:
            return LifeReceiptGridCamera(
                scale: 1.13,
                anchor: .center,
                offset: .zero
            )
        case .yourTime:
            return LifeReceiptGridCamera(
                scale: 1.18,
                anchor: .center,
                offset: .zero
            )
        case .phoneTakeover:
            return LifeReceiptGridCamera(
                scale: 1.24,
                anchor: .center,
                offset: .zero
            )
        case .phoneTruth:
            return LifeReceiptGridCamera(
                scale: 1.28,
                anchor: .center,
                offset: .zero
            )
        case .rescue:
            return LifeReceiptGridCamera(
                scale: 1.12,
                anchor: .center,
                offset: .zero
            )
        }
    }

    private var receiptCameraAnimation: Animation {
        if reduceMotion { return .linear(duration: 0.01) }

        switch beat {
        case .phoneTakeover, .phoneTruth:
            return .easeInOut(duration: 0.95)
        case .rescue:
            return .easeInOut(duration: 0.82)
        default:
            return .easeInOut(duration: 0.70)
        }
    }

    private var squareAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.34)
    }

    private var accessibilityGridLabel: String {
        switch beat {
        case .allLife:
            return "80 life squares"
        case .yearsAhead:
            return "\(squareModel.yearsAheadCount) visible years left after age"
        case .sleepLocked:
            return "\(squareModel.yearsAheadCount) years ahead, with sleep years removed as a connected block"
        case .workSchoolLocked:
            return "\(squareModel.yearsAheadCount - squareModel.sleepCount) years left after sleep, with work and school years removed"
        case .yourTime:
            return "\(squareModel.yourTimeBeforePhoneCount) your time squares"
        case .phoneTakeover, .phoneTruth:
            return "\(squareModel.phoneCount) phone squares taking from your time"
        case .rescue:
            return "\(squareModel.protectedPhoneCount) phone squares protected by Memo"
        }
    }

    private var dailyHoursLabel: String {
        OnboardingScreenTimeHoursFormatter.dailyLabel(
            hours: dailyScreenTimeHours,
            isEstimate: isEstimate
        )
    }

    private func startIntroReveal() {
        guard !introRevealDone else { return }
        guard !reduceMotion else {
            introRevealDone = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.easeOut(duration: 1.15)) {
                introRevealDone = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
        }
    }

    private func resetReceiptForManualStepping() {
        guard !isLoadingScreenTime else { return }
        guard previewBeat == nil else { return }
        animationTask?.cancel()
        beat = .allLife
        receiptFinished = false
        receiptLineFinished = false
        isAdvancingBeat = false
        activeDotIndex = nil
    }

    private func handleReceiptCTA() {
        guard canUseReceiptCTA else { return }
        if beat == .rescue {
            onContinue()
            return
        }
        guard let nextBeat = nextManualBeat(after: beat) else { return }
        advanceReceipt(to: nextBeat)
    }

    private func nextManualBeat(after beat: OnboardingLifeReceiptBeat) -> OnboardingLifeReceiptBeat? {
        switch beat {
        case .allLife:
            return .yearsAhead
        case .yearsAhead:
            return .sleepLocked
        case .sleepLocked:
            return .workSchoolLocked
        case .workSchoolLocked:
            return .yourTime
        case .yourTime:
            return .phoneTakeover
        case .phoneTruth:
            return .rescue
        case .phoneTakeover, .rescue:
            return nil
        }
    }

    private func advanceReceipt(to nextBeat: OnboardingLifeReceiptBeat) {
        animationTask?.cancel()
        isAdvancingBeat = true
        receiptLineFinished = false
        receiptFinished = false
        activeDotIndex = nil

        withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.58, dampingFraction: 0.86)) {
            beat = nextBeat
        }

        // The takeover camera push should be felt, not just seen.
        if nextBeat == .phoneTakeover && !reduceMotion {
            takenThroughIndex = -1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.70)
        }

        animationTask = Task { @MainActor in
            let hapticDuration = await playHapticSequence(for: nextBeat)
            guard !Task.isCancelled else { return }

            if nextBeat == .phoneTakeover {
                try? await Task.sleep(nanoseconds: nanoseconds(reduceMotion ? 0.12 : 0.72))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.58, dampingFraction: 0.86)) {
                    beat = .phoneTruth
                }
                receiptLineFinished = false
                if !reduceMotion {
                    await playTruthBeat()
                }
                isAdvancingBeat = false
                return
            }

            let hold = max(reduceMotion ? 0.04 : 0.22, min(0.65, duration(for: nextBeat) - hapticDuration))
            try? await Task.sleep(nanoseconds: nanoseconds(hold))
            guard !Task.isCancelled else { return }
            isAdvancingBeat = false
        }
    }

    @discardableResult
    private func applyPreviewBeatIfNeeded() -> Bool {
        guard let previewBeat else { return false }
        animationTask?.cancel()
        beat = previewBeat
        receiptFinished = previewBeat == .rescue
        receiptLineFinished = true
        isAdvancingBeat = false
        activeDotIndex = nil
        return true
    }

    private func duration(for beat: OnboardingLifeReceiptBeat) -> Double {
        if reduceMotion { return 0.12 }
        switch beat {
        case .allLife:
            return 0.72
        case .yearsAhead:
            return max(4.20, Double(squareModel.yearsAheadCount) * hapticInterval(for: beat) + 0.92)
        case .sleepLocked:
            return max(2.25, Double(squareModel.sleepCount) * hapticInterval(for: beat) + 0.68)
        case .workSchoolLocked:
            return max(1.85, Double(squareModel.workSchoolCount) * hapticInterval(for: beat) + 0.62)
        case .yourTime:
            return max(2.65, Double(squareModel.yourTimeBeforePhoneCount) * hapticInterval(for: beat) + 0.74)
        case .phoneTakeover:
            return max(9.40, Double(squareModel.phoneCount) * hapticInterval(for: beat) + 1.20)
        case .phoneTruth:
            return 2.50
        case .rescue:
            return max(1.72, Double(squareModel.protectedPhoneCount) * hapticInterval(for: beat) + 0.68)
        }
    }

    private func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0.01, seconds) * 1_000_000_000)
    }

    private func squareDelay(index: Int, role: OnboardingLifeReceiptSquareRole, roles: [OnboardingLifeReceiptSquareRole]) -> Double {
        guard !reduceMotion else { return 0 }
        guard isRoleAnimated(role, for: beat) else { return 0 }
        let ordinal = roles.prefix(index).filter { $0 == role }.count
        let count = roles.filter { $0 == role }.count
        return tickOffset(ordinal: ordinal, count: count, for: beat)
    }

    /// Gap before tick `ordinal+1` of `count`. The takeover accelerates —
    /// gaps shrink from 0.62s to 0.30s so losing squares feels like losing
    /// control. All other beats keep their fixed cadence.
    private func tickGap(ordinal: Int, count: Int, for beat: OnboardingLifeReceiptBeat) -> Double {
        guard beat == .phoneTakeover, count > 1 else {
            return hapticInterval(for: beat)
        }
        let progress = Double(ordinal) / Double(count - 1)
        return 0.62 - 0.32 * progress
    }

    /// Cumulative start offset for tick `ordinal` — keeps the square reveal
    /// delays and the haptic loop on the exact same schedule.
    private func tickOffset(ordinal: Int, count: Int, for beat: OnboardingLifeReceiptBeat) -> Double {
        guard beat == .phoneTakeover, count > 1 else {
            return Double(ordinal) * hapticInterval(for: beat)
        }
        var offset = 0.0
        for i in 0..<ordinal {
            offset += tickGap(ordinal: i, count: count, for: beat)
        }
        return offset
    }

    private func isRoleAnimated(_ role: OnboardingLifeReceiptSquareRole, for beat: OnboardingLifeReceiptBeat) -> Bool {
        switch beat {
        case .yearsAhead:
            return role == .future
        case .sleepLocked:
            return role == .sleep
        case .workSchoolLocked:
            return role == .workSchool
        case .yourTime:
            return role == .yourTime
        case .phoneTakeover:
            return role == .phone
        case .rescue:
            return role == .protectedPhone
        case .allLife, .phoneTruth:
            return false
        }
    }

    @MainActor
    private func playHapticSequence(for beat: OnboardingLifeReceiptBeat) async -> Double {
        guard !reduceMotion else { return 0 }
        let indexes = hapticIndexes(for: beat)

        if beat == .phoneTruth {
            await playTruthBeat()
            return 0.30
        }

        if beat == .rescue {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        guard !indexes.isEmpty else { return 0 }
        // The takeover gets the sharp rigid knock; counting beats roll light.
        let generator = UIImpactFeedbackGenerator(style: beat == .phoneTakeover ? .rigid : .light)
        let finale = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        var elapsed = 0.0

        for (ordinal, index) in indexes.enumerated() {
            guard !Task.isCancelled else {
                activeDotIndex = nil
                return elapsed
            }
            activeDotIndex = index
            if beat == .phoneTakeover {
                withAnimation(.easeOut(duration: 0.30)) {
                    takenThroughIndex = index
                }
            }
            if beat == .phoneTakeover && ordinal == indexes.count - 1 {
                finale.impactOccurred()
            } else {
                generator.impactOccurred(intensity: hapticIntensity(for: beat, ordinal: ordinal, count: indexes.count))
            }
            // Re-prepare on slow cadences so the engine stays warm between ticks.
            generator.prepare()
            if beat == .phoneTakeover && ordinal >= indexes.count - 3 {
                finale.prepare()
            }
            let gap = tickGap(ordinal: ordinal, count: indexes.count, for: beat)
            try? await Task.sleep(nanoseconds: nanoseconds(gap))
            elapsed += gap
        }

        activeDotIndex = nil
        if beat == .phoneTakeover {
            takenThroughIndex = Int.max
        }

        if beat == .rescue {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        return elapsed
    }

    /// "That is X years." lands as a double hit — rigid then heavy — while
    /// every phone square pulses once in unison.
    @MainActor
    private func playTruthBeat() async {
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        rigid.prepare()
        heavy.prepare()
        withAnimation(.easeOut(duration: 0.22)) { truthPulse = true }
        rigid.impactOccurred()
        try? await Task.sleep(nanoseconds: nanoseconds(0.09))
        heavy.impactOccurred()
        try? await Task.sleep(nanoseconds: nanoseconds(0.16))
        withAnimation(.easeOut(duration: 0.25)) { truthPulse = false }
    }

    private func hapticIndexes(for beat: OnboardingLifeReceiptBeat) -> [Int] {
        let roles = squareModel.viewportRoles(for: beat)
        return roles.enumerated().compactMap { index, role in
            isRoleAnimated(role, for: beat) ? index : nil
        }
    }

    private func hapticInterval(for beat: OnboardingLifeReceiptBeat) -> Double {
        switch beat {
        case .yearsAhead:
            return 0.095
        case .sleepLocked:
            return 0.125
        case .workSchoolLocked:
            return 0.140
        case .yourTime:
            return 0.110
        case .phoneTakeover:
            return 0.500
        case .rescue:
            return 0.160
        case .allLife, .phoneTruth:
            return 0.076
        }
    }

    private func hapticIntensity(for beat: OnboardingLifeReceiptBeat, ordinal: Int, count: Int) -> CGFloat {
        switch beat {
        case .phoneTakeover:
            // Intensity climbs with the accelerating cadence (the final square
            // fires a full heavy impact in the loop instead).
            let progress = CGFloat(ordinal) / CGFloat(max(count - 1, 1))
            return 0.70 + 0.30 * progress
        case .rescue:
            return 0.75
        default:
            return 0.55
        }
    }
}

private struct LifeReceiptSquare: View {
    let role: OnboardingLifeReceiptSquareRole
    let isDamageFocus: Bool
    let isRescueBeat: Bool
    let isActive: Bool
    var isPulsing: Bool = false
    /// Phone dot the takeover sweep hasn't reached yet — still renders as a
    /// living "yours" dot so the sweep visibly extinguishes it.
    var isAwaitingTake: Bool = false
    /// Idle heartbeat — a slow shimmer wave drifts across the grid on the
    /// opening beats. Alive dots make the takeover mean something.
    var isBreathing: Bool = false
    var breatheDelay: Double = 0

    @State private var breathe = false

    /// During the takeover, taken dots read as embers — flared once (isActive),
    /// then dimmed and shrunk. Alive → extinguished is the payload.
    private var isEmber: Bool {
        role == .phone && isDamageFocus && !isActive && !isPulsing && !isAwaitingTake
    }

    var body: some View {
        Circle()
            .fill(isAwaitingTake ? OB.success.opacity(0.20) : fill)
            .overlay(
                Circle()
                    .stroke(isAwaitingTake ? OB.success.opacity(0.65) : stroke, lineWidth: 1)
            )
            // Orb material: a small top-leading highlight turns flat circles
            // into beads with mass.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(role == .life ? 0.10 : 0.28), .clear],
                            center: UnitPoint(x: 0.34, y: 0.30),
                            startRadius: 0,
                            endRadius: 9
                        )
                    )
            )
            .overlay {
                if isActive {
                    Circle()
                        .stroke(activeColor.opacity(0.70), lineWidth: 2)
                        .scaleEffect(role == .phone ? 2.05 : 1.85)
                        .opacity(0.82)
                }
            }
            .shadow(color: glow, radius: glowRadius, y: 3)
            .scaleEffect(isPulsing ? 1.16 : (isActive ? activeScale : (isEmber ? 0.92 : 1)))
            .scaleEffect(breathe ? 1.08 : 1.0)
            .brightness(breathe ? 0.10 : 0)
            .saturation(isEmber ? 0.72 : 1.0)
            .opacity(opacity * (isEmber ? 0.78 : 1))
            .animation(.easeOut(duration: role == .phone ? 0.30 : 0.22), value: isActive)
            .animation(.easeOut(duration: 0.22), value: isPulsing)
            .animation(.easeOut(duration: 0.35), value: isEmber)
            .onAppear { syncBreathing(isBreathing) }
            .onChange(of: isBreathing) { _, nowBreathing in
                syncBreathing(nowBreathing)
            }
    }

    private func syncBreathing(_ on: Bool) {
        if on {
            withAnimation(
                .easeInOut(duration: 2.2)
                    .repeatForever(autoreverses: true)
                    .delay(breatheDelay)
            ) {
                breathe = true
            }
        } else if breathe {
            withAnimation(.easeOut(duration: 0.35)) {
                breathe = false
            }
        }
    }

    private var fill: Color {
        switch role {
        case .life:
            return OB.fg2.opacity(0.16)
        case .lived:
            return OB.accent.opacity(0.94)
        case .future:
            return OB.accent.opacity(0.24)
        case .sleep:
            return OB.memoPurple.opacity(0.72)
        case .workSchool:
            return OB.fg3.opacity(0.34)
        case .yourTime:
            return isDamageFocus ? OB.success.opacity(0.08) : OB.success.opacity(0.18)
        case .phone:
            return OB.coral
        case .protectedPhone:
            return OB.accent
        }
    }

    private var stroke: Color {
        switch role {
        case .life:
            return OB.fg2.opacity(0.16)
        case .future:
            return OB.accent.opacity(0.34)
        case .lived:
            return OB.accent.opacity(0.66)
        case .sleep:
            return OB.memoPurple.opacity(0.58)
        case .workSchool:
            return OB.fg3.opacity(0.30)
        case .yourTime:
            return OB.success.opacity(isDamageFocus ? 0.42 : 0.76)
        case .phone:
            return OB.coral.opacity(0.86)
        case .protectedPhone:
            return OB.accent.opacity(0.90)
        }
    }

    private var glow: Color {
        switch role {
        case .yourTime:
            return OB.success.opacity(isDamageFocus ? 0.04 : 0.18)
        case .phone:
            return OB.coral.opacity(isDamageFocus ? 0.52 : 0.34)
        case .protectedPhone:
            return OB.accent.opacity(0.34)
        case .future, .lived:
            return OB.accent.opacity(0.12)
        default:
            return .clear
        }
    }

    private var opacity: Double {
        if isDamageFocus {
            switch role {
            case .phone:
                return 1
            case .yourTime:
                return 0.58
            case .lived, .sleep, .workSchool:
                return 0.50
            default:
                return 0.42
            }
        }

        if isRescueBeat {
            switch role {
            case .phone:
                return 0.96
            case .protectedPhone:
                return 1
            case .yourTime:
                return 0.74
            default:
                return 0.68
            }
        }

        switch role {
        case .sleep, .workSchool, .lived:
            return 0.86
        default:
            return 1
        }
    }

    private var activeColor: Color {
        switch role {
        case .phone:
            return OB.coral
        case .future, .protectedPhone, .lived:
            return OB.accent
        case .sleep:
            return OB.memoPurple
        case .yourTime:
            return OB.success
        default:
            return OB.fg2
        }
    }

    private var glowRadius: CGFloat {
        switch role {
        case .phone where isDamageFocus:
            return 13
        case .phone, .protectedPhone:
            return 10
        case .yourTime:
            return 6
        default:
            return 7
        }
    }

    private var activeScale: CGFloat {
        role == .phone ? 1.24 : 1.14
    }
}

struct OnboardingMemoPlanView: View {
    let selectedGoals: Set<UserFocusGoal>
    var selectedGoalOrder: [UserFocusGoal] = []
    /// Drives the full-bleed atmosphere rendered at the onboarding root
    /// (pageAtmosphere) — the page slot can't reach behind the progress bar.
    @Binding var atmosphereVisible: Bool
    let onContinue: () -> Void

    private enum DemoStage {
        case pickApp
        case blocked
        case machine
        case won
    }

    @State private var appeared = false
    @State private var stage: DemoStage = .pickApp
    @State private var blockedAppAsset: String?
    @State private var demoLanded = false
    @State private var landedCaptionVisible = false
    @State private var showingGame = false
    @State private var gameCompleted = false

    private var subheadText: String {
        switch stage {
        case .pickApp, .blocked:
            return "Tap the app you'd doomscroll right now."
        case .machine:
            return "No feed til you train. Spin."
        case .won:
            return "That's the whole loop. Feel the difference?"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: compact ? 6 : 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Here's the\ncounterattack.")
                        .font(.system(size: compact ? 30 : 35, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subheadText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(2)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: subheadText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, compact ? 4 : 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                // The demo IS the explanation: tap the app you'd doomscroll →
                // it gets BLOCKED → spin the machine → play the real rep.
                ZStack {
                    switch stage {
                    case .pickApp, .blocked:
                        appPickerBeat
                            .transition(.opacity)
                    case .machine, .won:
                        machineBeat(compact: compact)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .responsiveContent(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsDemoBottomBar {
                demoBottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .padding(.top, 14)
                    .background(
                        LinearGradient(
                            colors: [OB.bg.opacity(0), OB.bg.opacity(0.96), OB.bg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            atmosphereVisible = stage == .machine || stage == .won
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .onDisappear {
            atmosphereVisible = false
        }
        // The real Visual Memory — same game as the Train tab, same results
        // screen. Its Done button saves the exercise (which posts
        // workoutGameCompleted) and dismisses.
        .fullScreenCover(isPresented: $showingGame, onDismiss: {
            if gameCompleted {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    stage = .won
                }
            }
        }) {
            // Onboarding is dark-pinned; the cover doesn't inherit the page's
            // scheme on its own.
            VisualMemoryView()
                .preferredColorScheme(.dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutGameCompleted)) { notification in
            guard showingGame,
                  let raw = notification.userInfo?["exerciseType"] as? String,
                  raw == ExerciseType.visualMemory.rawValue else { return }
            gameCompleted = true
        }
    }

    // MARK: Bottom bar — changes with the demo stage

    private var showsDemoBottomBar: Bool {
        switch stage {
        case .pickApp, .blocked:
            return false
        case .machine:
            return demoLanded
        case .won:
            return true
        }
    }

    @ViewBuilder
    private var demoBottomBar: some View {
        switch stage {
        case .pickApp, .blocked:
            // Invisible placeholder keeps the layout stable until a CTA earns
            // its place.
            OBContinueButton(title: "Personalize my plan", action: {})
                .opacity(0)
                .disabled(true)
        case .machine:
            VStack(spacing: 10) {
                OBContinueButton(title: "Play it · win the rep") {
                    showingGame = true
                }

                Button {
                    onContinue()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(OB.fg3)
                }
                .buttonStyle(.plain)
            }
            .opacity(demoLanded ? 1 : 0)
            .disabled(!demoLanded)
        case .won:
            OBContinueButton(title: "Personalize my plan", action: onContinue)
        }
    }

    // MARK: Beat 1 — tap the app

    private var appPickerBeat: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            HStack(alignment: .center, spacing: 20) {
                demoAppIcon(asset: "logo-youtube", size: 66, rotation: -7)
                demoAppIcon(asset: "logo-tiktok", size: 92, rotation: 0)
                demoAppIcon(asset: "logo-instagram", size: 66, rotation: 7)
            }
            .frame(maxWidth: .infinity)

            Text("any of them. go ahead.")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(OB.fg3)
                .padding(.top, 30)
                .opacity(stage == .pickApp ? 1 : 0)

            Spacer(minLength: 20)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private func demoAppIcon(asset: String, size: CGFloat, rotation: Double) -> some View {
        let isBlocked = blockedAppAsset == asset && stage == .blocked

        return Button {
            blockApp(asset)
        } label: {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .rotationEffect(.degrees(rotation))
                .scaleEffect(isBlocked ? 0.92 : 1.0)
                .saturation(isBlocked ? 0.25 : 1.0)
                .overlay {
                    if isBlocked {
                        Text("BLOCKED")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(OB.coral)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(OB.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(OB.coral, lineWidth: 2)
                            )
                            .rotationEffect(.degrees(-12))
                            .transition(.scale(scale: 1.6).combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(stage != .pickApp)
        .accessibilityLabel("Open \(asset.replacingOccurrences(of: "logo-", with: ""))")
    }

    private func blockApp(_ asset: String) {
        blockedAppAsset = asset
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            stage = .blocked
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                stage = .machine
                atmosphereVisible = true
            }
        }
    }

    // MARK: Beat 2 — the machine

    private func machineBeat(compact: Bool) -> some View {
        VStack(spacing: 0) {
            FocusUnlockSlotMachine(
                mode: .demo,
                onLanded: { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        demoLanded = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            landedCaptionVisible = true
                        }
                    }
                }
            )
            .frame(maxWidth: compact ? 320 : 340)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            Group {
                if stage == .won {
                    VStack(spacing: 3) {
                        Text("REP WON. 10 MINUTES EARNED.")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(OB.success)
                            .shadow(color: OB.success.opacity(0.4), radius: 10)
                        Text("That's the price of the feed now.")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OB.fg2)
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    Text("That's the new price of a feed.")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .opacity(landedCaptionVisible ? 1 : 0)
                        .offset(y: landedCaptionVisible ? 0 : 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 8 : 12)

            Spacer(minLength: 0)
        }
    }
}


// MARK: - Pain Cards (NEW)
//
// Sits after Goals. Six specific Gen-Z pain statements presented one at a time
// inside a tall "receipt slip" with a torn perforation along its TOP edge. User
// taps "Caught me" to confess (CAUGHT stamp drops in the lower-right and the
// slip slides into the saved-receipt back-stack) or "Not me" to flick it away.
// Tap-based instead of swipe so gesture conflicts with TabView don't strand
// the user.

struct OnboardingPainCardsView: View {
    let onContinue: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int = 0
    @State private var receiptCount: Int = 0
    @State private var savedReceipts: [String] = []
    @State private var cardOffsetX: CGFloat = 0
    @State private var cardOffsetY: CGFloat = 0
    @State private var cardRotation: Double = 0
    @State private var cardScale: CGFloat = 1
    @State private var cardOpacity: Double = 1
    @State private var headlineVisible = false
    @State private var stackVisible = false
    @State private var mascotVisible = false
    @State private var buttonsVisible = false
    @State private var showCaughtStamp = false
    @State private var isAnimating = false

    private let painCards: [String] = [
        "I check my phone before I check the time",
        "I forget what I just read on a page",
        "I uninstall TikTok, then redownload by Friday",
        "I scroll until 2am even when I know better",
        "I open the same 4 apps in a loop",
        "I can't sit through a movie without my phone"
    ]

    private var currentCard: String {
        guard currentIndex < painCards.count else { return painCards.last ?? "" }
        return painCards[currentIndex]
    }

    // Cap at 3 visible saved slips (UI-SPEC §"Page 2 — Pain Cards" line ~431).
    // Empty state: render no back slips when nothing has been caught yet — per
    // CONTEXT D-01f, ambient filler text is meaningless and should be dropped.
    private var backReceipts: [ReceiptBackItem] {
        let saved = Array(savedReceipts.suffix(3).reversed())
        return saved.enumerated().map { index, _ in
            ReceiptBackItem(id: "saved-\(savedReceipts.count)-\(index)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Which ones are yours?")
                    .font(.brand(size: 31, weight: .heavy))
                    .foregroundStyle(OB.fg)
                    .lineSpacing(1)
                    .kerning(-0.4)

                Text("Tap what feels painfully familiar. Memo uses it to build your fight plan.")
                    .font(.brand(size: 15, weight: .semibold))
                    .foregroundStyle(OB.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .opacity(headlineVisible ? 1 : 0)
            .offset(y: headlineVisible ? 0 : 8)

            Spacer(minLength: 28)

            receiptStack
                .padding(.horizontal, 24)
                .opacity(stackVisible ? 1 : 0)
                .offset(y: stackVisible ? 0 : 24)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: { handleTap(caught: false) }) {
                    Text("Not me")
                        .font(.brand(size: 17, weight: .heavy))
                        .foregroundStyle(OB.fg2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(OB.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)

                Button(action: { handleTap(caught: true) }) {
                    Text("Caught me")
                        .font(.brand(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(OB.accent)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                )
                                .shadow(color: OB.accent.opacity(0.4), radius: 12, y: 4)
                                .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAnimating)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .opacity(buttonsVisible ? 1 : 0)
            .offset(y: buttonsVisible ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OB.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .onAppear {
            startEntrance()
        }
    }

    // The receipt stack: dim back slips (capped at 3) + the active front slip,
    // with the mascot peeking from the bottom-leading edge so its head/glasses
    // hover behind the stack but never cross into the active confession or
    // the action buttons below.
    private var receiptStack: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .top) {
                receiptBackStack

                PainReceiptSlip(
                    progressText: "\(currentIndex + 1) of \(painCards.count)",
                    label: "current receipt",
                    confession: currentCard,
                    showCaughtStamp: showCaughtStamp,
                    isActive: true
                )
                .scaleEffect(cardScale, anchor: .center)
                .rotationEffect(.degrees(cardRotation))
                .offset(x: cardOffsetX, y: cardOffsetY)
                .opacity(cardOpacity)
                .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.48, dampingFraction: 0.82), value: currentIndex)
            }
            .frame(maxWidth: .infinity)

            Image("mascot-thinking")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .rotationEffect(.degrees(mascotVisible ? -4 : -7))
                .scaleEffect(mascotVisible ? 1 : 0.9)
                .opacity(mascotVisible ? 1 : 0)
                .offset(x: 4, y: 18)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                .accessibilityHidden(true)
        }
    }

    private var receiptBackStack: some View {
        ZStack {
            let layers = Array(backReceipts.prefix(3).enumerated())
            ForEach(Array(layers.reversed()), id: \.element.id) { index, item in
                PainReceiptSlip(
                    progressText: "",
                    label: "saved receipt",
                    confession: "",
                    showCaughtStamp: false,
                    isActive: false
                )
                .id(item.id)
                .rotationEffect(.degrees(backLayerRotation(index)))
                .offset(x: backLayerX(index), y: backLayerY(index))
                .opacity(backLayerOpacity(index))
                .accessibilityHidden(true)
            }
        }
    }

    private func startEntrance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.38)) {
                headlineVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.50, dampingFraction: 0.82)) {
                stackVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.80)) {
                mascotVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.30)) {
                buttonsVisible = true
            }
        }
    }

    private func handleTap(caught: Bool) {
        guard !isAnimating else { return }
        isAnimating = true

        let answeredCard = currentCard
        let nextReceiptCount = receiptCount + (caught ? 1 : 0)
        receiptCount = nextReceiptCount
        // Haptic fires BEFORE the visual animation per UI-SPEC. Both Reduce
        // Motion paths preserve haptic feedback (D-11).
        UIImpactFeedbackGenerator(style: caught ? .medium : .light).impactOccurred()

        if reduceMotion {
            // Reduce Motion: no scale-pop, no slide. Stamp shows at full scale
            // via opacity fade-in; slip exits via a 0.18s opacity fade.
            if caught { showCaughtStamp = true }
            withAnimation(.easeOut(duration: 0.18)) {
                cardOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                advance(after: answeredCard, caught: caught, finalReceiptCount: nextReceiptCount)
            }
            return
        }

        if caught {
            // Stamp scale-pop: 0.72 → 1.08 → 1.0 over 0.18s, hold, then slip
            // slides back into the stack with a +5° rotation.
            withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                showCaughtStamp = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.26)) {
                    cardOffsetX = 10
                    cardOffsetY = 18
                    cardRotation = 5
                    cardScale = 0.94
                    cardOpacity = 0.78
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                advance(after: answeredCard, caught: true, finalReceiptCount: nextReceiptCount)
            }
        } else {
            // Not me: flick left, rotate -9°, fade to 0 over 0.30s.
            withAnimation(.easeIn(duration: 0.30)) {
                cardOffsetX = -340
                cardRotation = -9
                cardOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                advance(after: answeredCard, caught: false, finalReceiptCount: nextReceiptCount)
            }
        }
    }

    private func advance(after answeredCard: String, caught: Bool, finalReceiptCount: Int) {
        if caught {
            savedReceipts.append(answeredCard)
        }

        if currentIndex < painCards.count - 1 {
            currentIndex += 1
            showCaughtStamp = false
            cardRotation = 0
            cardScale = reduceMotion ? 1 : 0.98
            cardOffsetX = 0
            cardOffsetY = reduceMotion ? 0 : 24
            cardOpacity = 0
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.82)) {
                cardOffsetY = 0
                cardScale = 1
                cardOpacity = 1
            }
            isAnimating = false
        } else {
            Analytics.onboardingStep(step: "painCards")
            onContinue(finalReceiptCount)
        }
    }

    // Back-stack geometry per UI-SPEC §"Page 2 — Pain Cards" visual spec table.
    // Slip 1: rot +5°, y +18, x +10, opacity 0.78
    // Slip 2: rot -4°, y +36, x -8,  opacity 0.55
    // Slip 3: rot +8°, y +54, x +14, opacity 0.35  (only if ≥3 caught)
    private func backLayerRotation(_ index: Int) -> Double {
        [5, -4, 8][min(index, 2)]
    }

    private func backLayerX(_ index: Int) -> CGFloat {
        [10, -8, 14][min(index, 2)]
    }

    private func backLayerY(_ index: Int) -> CGFloat {
        [18, 36, 54][min(index, 2)]
    }

    private func backLayerOpacity(_ index: Int) -> Double {
        [0.78, 0.55, 0.35][min(index, 2)]
    }
}

private struct ReceiptBackItem {
    let id: String
}

// MARK: - Pain Receipt Slip
//
// Tall receipt slip (210pt min-height) with a dotted perforation line along
// the TOP edge so the slip reads as a torn-off coupon header rather than a
// content card with a divider through its middle. Active state shows the
// confession text large in the body; back-stack state shows ONLY the dim
// "saved receipt" label — the confession body is intentionally blank to
// kill the meaningless "feed loop" filler from the first Codex pass (D-01f).
private struct PainReceiptSlip: View {
    let progressText: String
    let label: String
    let confession: String
    let showCaughtStamp: Bool
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                // Micro progress + active label — only render on the active slip.
                // Brand 11pt semibold, lowercase ("3 of 6") to kill the "1 0F 6"
                // misread that the first Codex pass shipped with a monospaced +
                // uppercase treatment (D-01a).
                if isActive && !progressText.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(progressText)
                            .font(.brand(size: 11, weight: .semibold))
                            .foregroundStyle(OB.fg3)

                        Text("·")
                            .font(.brand(size: 11, weight: .semibold))
                            .foregroundStyle(OB.fg3)

                        Text(label)
                            .font(.brand(size: 12, weight: .medium))
                            .foregroundStyle(OB.fg3)
                    }
                } else {
                    // Back slips: ONLY the dim "saved receipt" label, no body
                    // text. Empty body is intentional — see D-01f.
                    Text(label)
                        .font(.brand(size: 12, weight: .medium))
                        .foregroundStyle(OB.fg3)
                }

                if isActive {
                    Text(confession)
                        .font(.brand(size: 22, weight: .heavy))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(2)
                        .kerning(-0.4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(confession)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22) // 18pt vertical + 4pt clearance below the perforation dashes
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OB.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isActive ? OB.accent.opacity(0.45) : Color.white.opacity(0.08),
                                    lineWidth: isActive ? 1.5 : 1)
                    }
                    .shadow(color: isActive ? OB.accent.opacity(0.18) : .black.opacity(0.32),
                            radius: isActive ? 22 : 14, y: 10)
                    // Perforation rides on the TOP edge — inset 16pt from each
                    // side, dotted [2,5] white@14% — so the slip reads as a
                    // torn-off coupon header (D-01e).
                    .overlay(alignment: .top) {
                        ReceiptPerforation()
                            .stroke(Color.white.opacity(0.14),
                                    style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                            .padding(.top, 11)
                    }
            }

            if showCaughtStamp && isActive {
                CaughtStamp()
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CaughtStamp: View {
    var body: some View {
        Text("CAUGHT")
            .font(.system(size: 22, weight: .heavy, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(OB.coral)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(OB.coral.opacity(0.72), lineWidth: 2)
            }
            .rotationEffect(.degrees(-8))
    }
}

// Top-edge perforation: draws a horizontal line at y = 0 of the bounding rect.
// The frame this is rendered into is already inset 16pt from each side and
// padded 11pt down from the slip's top edge by the parent layout.
private struct ReceiptPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        return path
    }
}

// MARK: - Comparison (NEW)
//
// Sits after Brain Age Reveal. Two-column WITHOUT/WITH contrast personalized
// using the user's pickup count, daily hours, and brain age from earlier
// pages. Makes the cost of inaction concrete in their own terms.

struct OnboardingComparisonView: View {
    let pickupCount: Int
    let dailyHours: Double
    let brainAge: Int?
    let onContinue: () -> Void

    @State private var headlineVisible = false
    @State private var rowsVisible: [Bool] = [false, false, false, false]
    @State private var footerVisible = false

    private struct Row { let without: String; let with: String }

    private var rows: [Row] {
        let pickups = max(pickupCount, 80)
        let hrs = max(dailyHours, 1)
        // Mirrors OnboardingPersonalSolutionView.memoReductionFraction
        // (0.75) — the comparison row must claim the same reclaim as the
        // plan-reveal page right before it, or the funnel reads off-key.
        let saved = max(hrs * 0.75, 0.5)
        let brainAgeLine = brainAge.map { "Brain Age \($0) drifts up" } ?? "Brain rot keeps compounding"
        return [
            Row(without: "Open the same apps \(pickups)\u{00D7}", with: "Open after training"),
            Row(without: "\(formatHrs(hrs)) leaks into the feed", with: "\(formatHrs(saved)) back in play"),
            Row(without: brainAgeLine, with: "Train the score down"),
            Row(without: "You're the product", with: "You're the customer")
        ]
    }

    private func formatHrs(_ h: Double) -> String {
        let rounded = h.rounded()
        if abs(h - rounded) < 0.05 { return "\(Int(rounded))h" }
        return String(format: "%.1fh", h)
    }

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()

            comparisonAtmosphere

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Same phone.\nDifferent rules.")
                        .font(.system(size: 37, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(1)
                        .kerning(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Without Memo, the feed wins by default. With Memo, every open costs reps.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 8)

                Spacer().frame(height: 26)

                splitLedger
                    .padding(.horizontal, 24)

                Spacer()

                Text("Memo doesn't ask for more willpower. It changes the rules.")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 14)
                    .opacity(footerVisible ? 1 : 0)
                    .offset(y: footerVisible ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OBContinueButton(title: "See why Memo works", action: {
                Analytics.onboardingStep(step: "comparison")
                onContinue()
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .onAppear { startEntrance() }
    }

    private var comparisonAtmosphere: some View {
        ZStack {
            Circle()
                .fill(OB.coral.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 64)
                .offset(x: -150, y: -160)

            Circle()
                .fill(OB.accent.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 160, y: 140)
        }
    }

    private var splitLedger: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Without Memo")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("With Memo")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .textCase(.uppercase)
            .tracking(1.1)
            .padding(.bottom, 13)

            Rectangle()
                .fill(OB.border)
                .frame(height: 1)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                comparisonRow(index: index, row: row)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(OB.border)
                        .frame(height: 1)
                }
            }
        }
    }

    private func comparisonRow(index: Int, row: Row) -> some View {
        let isVisible = index < rowsVisible.count && rowsVisible[index]

        return HStack(alignment: .center, spacing: 0) {
            Text(row.without)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(index == 3 ? OB.coral : OB.fg.opacity(0.82))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)

            ZStack {
                Rectangle()
                    .fill(OB.border)
                    .frame(width: 1)

                Circle()
                    .fill(index == 3 ? OB.accent : OB.bg)
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(index == 3 ? OB.accent : OB.border, lineWidth: 1)
                    }
            }
            .frame(width: 22)

            Text(row.with)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(index == 3 ? OB.accent : OB.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 14)
        }
        .padding(.vertical, 18)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
    }

    private func startEntrance() {
        rowsVisible = Array(repeating: false, count: rows.count)
        footerVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.4)) { headlineVisible = true }
        }
        for i in 0..<rows.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42 + Double(i) * 0.12) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    rowsVisible[i] = true
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.08) {
            withAnimation(.easeOut(duration: 0.4)) { footerVisible = true }
        }
    }
}

// MARK: - Social Proof / Founder (NEW)
//
// Pivoted from "testimonials" to David vs Goliath since Memori has no v2 reviews
// yet. The indie founder origin + leaderboard preview together make the
// social-proof case stronger than fake testimonials would. Surfaces the
// Compete tab existence which is currently buried.

struct OnboardingSocialProofView: View {
    let onContinue: () -> Void

    @State private var headlineVisible = false
    @State private var quoteVisible = false
    @State private var leaderboardVisible = false
    @State private var taglineVisible = false

    private let leaderboardPreview: [(rank: Int, name: String, score: Int)] = [
        (1, "sarah_m_", 921),
        (2, "noahduke", 887),
        (3, "luc.codes", 852),
        (47, "you?", 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                OBEyebrow(text: "NOT A CORPORATION")

                (Text("Built by ") + Text("one developer").foregroundColor(OB.accent) + Text("."))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .lineSpacing(1)
                    .kerning(-0.4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Up against an industry spending $57B/year on you.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OB.fg2)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .opacity(headlineVisible ? 1 : 0)
            .offset(y: headlineVisible ? 0 : 8)

            Spacer().frame(height: 22)

            // Founder pull-quote
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(OB.accent)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{201C}I built Memo because I couldn't put TikTok down either. No VC. No ads. Just an app on your side.\u{201D}")
                        .font(.system(size: 16, weight: .medium).italic())
                        .foregroundStyle(OB.fg)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\u{2014} Dylan, founder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OB.fg3)
                }
            }
            .padding(.horizontal, 28)
            .opacity(quoteVisible ? 1 : 0)
            .offset(y: quoteVisible ? 0 : 6)

            Spacer().frame(height: 24)

            // Leaderboard preview
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    OBEyebrow(text: "LEADERBOARDS")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(OB.success).frame(width: 6, height: 6)
                            .shadow(color: OB.success, radius: 3)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(OB.success)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(OB.success.opacity(0.12)))
                }

                VStack(spacing: 0) {
                    ForEach(Array(leaderboardPreview.enumerated()), id: \.offset) { i, entry in
                        leaderboardRow(rank: entry.rank, name: entry.name, score: entry.score, isYou: entry.name == "you?")
                        if i < leaderboardPreview.count - 1 {
                            Divider().overlay(OB.border)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(OB.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(OB.border, lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 28)
            .opacity(leaderboardVisible ? 1 : 0)
            .offset(y: leaderboardVisible ? 0 : 8)

            Spacer()

            Text("Compete weekly. Climb monthly. Live now.")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(OB.fg3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 14)
                .opacity(taglineVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OB.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            OBContinueButton(title: "Set up Focus Mode", action: {
                Analytics.onboardingStep(step: "socialProof")
                onContinue()
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear { startEntrance() }
    }

    private func leaderboardRow(rank: Int, name: String, score: Int, isYou: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(isYou ? OB.accent : OB.fg2)
                .frame(width: 28, alignment: .leading)

            Text(name)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(isYou ? OB.accent : OB.fg)

            Spacer()

            if isYou {
                Text("waiting on you")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OB.fg3)
            } else {
                Text("\(score)")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(OB.fg)
            }
        }
        .padding(.vertical, 10)
    }

    private func startEntrance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.4)) { headlineVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.45)) { quoteVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                leaderboardVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.4)) { taglineVisible = true }
        }
    }
}

// MARK: - Differentiation / Paid Because You're The Customer
//
// Final objection-handler before paywall. This is not a values list; it is a
// pricing-positioning argument with one receipt artifact users can remember.

struct OnboardingDifferentiationView: View {
    let onContinue: () -> Void

    @State private var headlineVisible = false
    @State private var receiptVisible = false
    @State private var receiptLinesVisible: [Bool] = [false, false, false, false]
    @State private var taglineVisible = false

    private let receiptLines = [
        "NO ADS",
        "NO DATA SOLD",
        "YOU'RE THE CUSTOMER",
        "TRAIN BEFORE YOU SCROLL"
    ]

    var body: some View {
        ZStack {
            OB.bg.ignoresSafeArea()

            differentiationAtmosphere

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    (Text("Free apps\nsell you.\n") + Text("Memo works\nfor you.").foregroundColor(OB.accent))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(1)
                        .kerning(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Social media is free because your attention pays the bill. Memo is paid because you're the customer.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 8)

                Spacer().frame(height: 28)

                receiptArtifact
                    .padding(.horizontal, 28)
                    .opacity(receiptVisible ? 1 : 0)
                    .scaleEffect(receiptVisible ? 1 : 0.96)
                    .rotationEffect(.degrees(receiptVisible ? -1.2 : 0))

                Spacer()

                HStack(alignment: .top, spacing: 12) {
                    Image("mascot-thinking")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)

                    Text("Built by one developer who got tired of losing to the feed too.")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
                .opacity(taglineVisible ? 1 : 0)
                .offset(y: taglineVisible ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            OBContinueButton(title: "Unlock my plan", action: {
                Analytics.onboardingStep(step: "differentiation")
                onContinue()
            })
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
        .onAppear { startEntrance() }
    }

    private var differentiationAtmosphere: some View {
        ZStack {
            Circle()
                .fill(OB.accent.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 78)
                .offset(x: 150, y: -180)

            Circle()
                .fill(OB.memoPurple.opacity(0.10))
                .frame(width: 250, height: 250)
                .blur(radius: 72)
                .offset(x: -150, y: 180)
        }
    }

    private var receiptArtifact: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Memo")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)

                Spacer()

                Text("PAID, NOT FARMED")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(OB.fg3)
            }
            .padding(.bottom, 16)

            Rectangle()
                .fill(OB.border)
                .frame(height: 1)

            ForEach(Array(receiptLines.enumerated()), id: \.offset) { index, line in
                receiptLine(index: index, text: line)
                if index < receiptLines.count - 1 {
                    Rectangle()
                        .fill(OB.border)
                        .frame(height: 1)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(OB.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(OB.border.opacity(1.4), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 24, y: 16)
        }
    }

    private func receiptLine(index: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: index == 3 ? "bolt.fill" : "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(OB.accent)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(OB.fg)

            Spacer()
        }
        .padding(.vertical, 15)
        .opacity(receiptLinesVisible[index] ? 1 : 0)
        .offset(x: receiptLinesVisible[index] ? 0 : -10)
    }

    private func startEntrance() {
        receiptLinesVisible = Array(repeating: false, count: receiptLines.count)
        receiptVisible = false
        taglineVisible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.4)) { headlineVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                receiptVisible = true
            }
        }
        for i in 0..<receiptLines.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62 + Double(i) * 0.11) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    receiptLinesVisible[i] = true
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.4)) { taglineVisible = true }
        }
    }
}

#if DEBUG
#Preview("Pain Cards") {
    OnboardingPainCardsView(onContinue: { _ in })
}

#Preview("Comparison") {
    OnboardingComparisonView(pickupCount: 287, dailyHours: 4.2, brainAge: 38, onContinue: {})
}

#Preview("Social Proof") {
    OnboardingSocialProofView(onContinue: {})
}

#Preview("Differentiation") {
    OnboardingDifferentiationView(onContinue: {})
}
#endif

// MARK: - Linear Congruential RNG
//
// Tiny deterministic RandomNumberGenerator used by PlanRevealBackdrop's
// permuted logo grid. Same seed → same shuffle every render, so SwiftUI
// re-renders the grid identically across frames while still breaking the
// modulo-based row/column patterns. Not crypto-grade — just enough to
// scatter 6 logos across 77 tiles without visible repetition lines.

private struct LinearCongruentialRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        // Numerical Recipes constants — fast, well-distributed.
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Memo Plan Build Beats (NEW)
//
// Transient, auto-advancing beats shown after each data-collection milestone
// (goals / age / screen time). Memo "thinks", a speech bubble reflects the
// latest answer, and a new line snaps onto the cumulative "YOUR PLAN"
// clipboard. A final presenting beat (page 6) holds up the complete plan right
// before the hard paywall. Copy/clipboard content comes from the pure,
// unit-tested PlanBuildBeatContent model.

struct OnboardingPersonalizationQuestionView<Option: Identifiable & Equatable>: View where Option.ID == String {
    let title: String
    let subtitle: String
    let options: [Option]
    let selectedOption: Option?
    let emoji: (Option) -> String
    let label: (Option) -> String
    let onSelect: (Option) -> Void
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            // Measured against the inset-reduced content area, not the screen.
            let compact = proxy.size.height < 600

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                    Spacer().frame(height: compact ? 14 : 42)

                    VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                        Text(title)
                            .font(.system(size: compact ? 28 : 34, weight: .black, design: .rounded))
                            .foregroundStyle(OB.fg)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(OB.fg2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: compact ? 8 : 10) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(emoji(option))
                                        .font(.system(size: compact ? 21 : 24))
                                        .frame(width: 34, height: 34)

                                    Text(label(option))
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .foregroundStyle(OB.fg)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)

                                    Spacer(minLength: 8)

                                    ZStack {
                                        Circle()
                                            .stroke(isSelected(option) ? OB.accent : OB.border, lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if isSelected(option) {
                                            Circle()
                                                .fill(OB.accent)
                                                .frame(width: 10, height: 10)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: compact ? 50 : 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isSelected(option) ? OB.accent.opacity(0.16) : OB.surface.opacity(0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected(option) ? OB.accent.opacity(0.82) : OB.border, lineWidth: isSelected(option) ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, compact ? 2 : 10)

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 500, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Pinned so six options can never push the CTA off a short screen.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [OB.bg.opacity(0), OB.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
                .allowsHitTesting(false)

                Button(action: onContinue) {
                    Text(selectedOption == nil ? "Pick one" : "Continue")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selectedOption == nil ? OB.accent.opacity(0.34) : OB.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedOption == nil)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(OB.bg)
        }
    }

    private func isSelected(_ option: Option) -> Bool {
        selectedOption == option
    }
}

/// Thin AVPlayerLooper wrapper so beats can loop a bundled Memo clip.
/// Self-contained (its own host view) so it doesn't depend on the private
/// LoopingVideoPlayer in OnboardingView.swift. Transparent background +
/// aspect-fit so the alpha Memo composites cleanly on the dark onboarding bg.
struct OnboardingLoopingVideo: UIViewRepresentable {
    let videoName: String
    var videoExt: String = "mov"

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class HostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .clear
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExt) else { return view }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        context.coordinator.player = queue
        context.coordinator.looper = looper
        view.playerLayer.player = queue
        view.playerLayer.videoGravity = .resizeAspect
        queue.play()
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {}

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
        uiView.playerLayer.player = nil
    }
}

struct OnboardingPlanBuildBackground: View {
    var body: some View {
        ZStack {
            OB.bg

            LinearGradient(
                colors: [
                    OB.bg,
                    OB.surface.opacity(0.96),
                    OB.bg
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    OB.accent.opacity(0.24),
                    OB.memoPurple.opacity(0.08),
                    OB.bg.opacity(0)
                ],
                center: UnitPoint(x: 0.5, y: 0.30),
                startRadius: 12,
                endRadius: 330
            )

            RadialGradient(
                colors: [
                    OB.success.opacity(0.12),
                    OB.accent.opacity(0.06),
                    OB.bg.opacity(0)
                ],
                center: UnitPoint(x: 0.5, y: 0.69),
                startRadius: 24,
                endRadius: 300
            )

            RadialGradient(
                colors: [
                    OB.bg.opacity(0),
                    OB.bg.opacity(0.46)
                ],
                center: .center,
                startRadius: 190,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Transient full-screen beat shown after a data-collection milestone. Memo
/// "thinks", a bubble appears reflecting the latest answer, the new clipboard
/// line snaps in, then `onAdvance` fires automatically (no CTA).
struct OnboardingPlanBuildBeatOverlay: View {
    let beat: PlanBuildBeatContent.Beat
    let goals: Set<UserFocusGoal>
    var selectedGoalOrder: [UserFocusGoal] = []
    let age: Int
    let dailyScreenTimeHours: Double
    let isEstimate: Bool
    var protectTarget: PlanBuildBeatContent.ProtectTarget?
    var feedWinMoment: PlanBuildBeatContent.FeedWinMoment?
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bubbleVisible = false
    @State private var revealedLineCount = 0
    @State private var didStart = false

    private var content: PlanBuildBeatContent {
        PlanBuildBeatContent(beat: beat, goals: goals, selectedGoalOrder: selectedGoalOrder, age: age,
                             dailyScreenTimeHours: dailyScreenTimeHours, isEstimate: isEstimate,
                             protectTarget: protectTarget, feedWinMoment: feedWinMoment)
    }

    private var lines: [PlanBuildBeatContent.Line] {
        PlanBuildBeatContent.cumulativeLines(upTo: beat, goals: goals, selectedGoalOrder: selectedGoalOrder, age: age,
                                             dailyScreenTimeHours: dailyScreenTimeHours, isEstimate: isEstimate,
                                             protectTarget: protectTarget, feedWinMoment: feedWinMoment)
    }

    private var memoVideoName: String { "memo-building" }

    var body: some View {
        ZStack {
            OnboardingPlanBuildBackground()

            VStack(spacing: 18) {
                Text("MEMO IS BUILDING YOUR PLAN")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(OB.fg3)
                    .padding(.top, 40)

                memoView
                    .frame(width: 170, height: 170)

                speechBubble

                clipboard

                Spacer()
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: 500)
        }
        .onAppear(perform: start)
    }

    @ViewBuilder
    private var memoView: some View {
        if Bundle.main.url(forResource: memoVideoName, withExtension: "mov") != nil {
            OnboardingLoopingVideo(videoName: memoVideoName)
        } else if let img = UIImage(named: "focus-memo-neutral") {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(OB.surface)
        }
    }

    private var speechBubble: some View {
        Text(content.bubble)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(OB.fg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OB.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OB.border, lineWidth: 1)
            )
            .opacity(bubbleVisible ? 1 : 0)
            .offset(y: bubbleVisible ? 0 : 8)
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR PLAN")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(OB.fg3)

            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(OB.success).frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(OB.bg)
                    }
                    Text("\(line.label): \(line.value)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(OB.fg)
                }
                .opacity(idx < revealedLineCount ? 1 : 0)
                .offset(x: idx < revealedLineCount ? 0 : -10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OB.surface.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(OB.border, lineWidth: 1))
    }

    private func start() {
        guard !didStart else { return }
        didStart = true

        // The personalization beat adds two lines as one receipt moment.
        let addedLineCount = (beat == .personalization) ? 2 : 1
        let priorCount = max(0, lines.count - addedLineCount)
        revealedLineCount = priorCount

        if reduceMotion {
            bubbleVisible = true
            revealedLineCount = lines.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onAdvance() }
            return
        }

        withAnimation(.easeOut(duration: 0.35).delay(0.25)) { bubbleVisible = true }
        // New line snaps in after the bubble reads.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                revealedLineCount = lines.count
            }
        }
        // Auto-advance once the bubble and clipboard line have registered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { onAdvance() }
    }
}

/// Final beat, shown on page 6 right before the hard paywall. Memo flips to a
/// proud "presenting" pose, holds up the now-complete clipboard with a
/// "Personalized for you" stamp, then fires `onComplete` → paywall.
struct OnboardingPlanFinalBeatView: View {
    let goals: Set<UserFocusGoal>
    var selectedGoalOrder: [UserFocusGoal] = []
    let age: Int
    let dailyScreenTimeHours: Double
    let isEstimate: Bool
    var protectTarget: PlanBuildBeatContent.ProtectTarget?
    var feedWinMoment: PlanBuildBeatContent.FeedWinMoment?
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didStart = false
    @State private var stampVisible = false

    private var lines: [PlanBuildBeatContent.Line] {
        PlanBuildBeatContent.cumulativeLines(upTo: .final, goals: goals, selectedGoalOrder: selectedGoalOrder, age: age,
                                             dailyScreenTimeHours: dailyScreenTimeHours, isEstimate: isEstimate,
                                             protectTarget: protectTarget, feedWinMoment: feedWinMoment)
    }
    private var bubble: String {
        PlanBuildBeatContent(beat: .final, goals: goals, selectedGoalOrder: selectedGoalOrder, age: age,
                             dailyScreenTimeHours: dailyScreenTimeHours, isEstimate: isEstimate,
                             protectTarget: protectTarget, feedWinMoment: feedWinMoment).bubble
    }
    private var memoVideoName: String { "memo-presenting" }

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 18) {
                Spacer(minLength: 30)

                Group {
                    if Bundle.main.url(forResource: memoVideoName, withExtension: "mov") != nil {
                        OnboardingLoopingVideo(videoName: memoVideoName)
                    } else if let img = UIImage(named: "focus-memo-happy") {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 28, style: .continuous).fill(OB.surface)
                    }
                }
                .frame(width: 190, height: 190)

                Text(bubble)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("YOUR PLAN")
                            .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1.4)
                            .foregroundStyle(OB.fg3)
                        Spacer()
                        Text("PERSONALIZED FOR YOU")
                            .font(.system(size: 8, weight: .black, design: .monospaced)).tracking(1.2)
                            .foregroundStyle(OB.success)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(OB.success.opacity(0.14)))
                            .opacity(stampVisible ? 1 : 0)
                            .scaleEffect(stampVisible ? 1 : 0.8)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 9) {
                            ZStack {
                                Circle().fill(OB.success).frame(width: 18, height: 18)
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundStyle(OB.bg)
                            }
                            Text("\(line.label): \(line.value)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(OB.fg)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OB.surface.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(OB.border, lineWidth: 1))

                Spacer()
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: 500)
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        let stampDelay = reduceMotion ? 0.2 : 0.8
        let advanceDelay = reduceMotion ? 1.2 : 2.8
        DispatchQueue.main.asyncAfter(deadline: .now() + stampDelay) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { stampVisible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + advanceDelay) { onComplete() }
    }
}
