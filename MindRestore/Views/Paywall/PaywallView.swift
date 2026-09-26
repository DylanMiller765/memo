import SwiftUI
import StoreKit

// MARK: - Paywall plans

private enum PaywallPlan: String, CaseIterable {
    case annual, weekly

    var hasTrial: Bool { self == .annual }
    var analyticsName: String { rawValue }

    var productID: String {
        switch self {
        case .annual: return StoreService.annualUltraProductID
        case .weekly: return StoreService.weeklyUltraProductID
        }
    }
}

struct PaywallPersonalizationContent: Equatable {
    let protectTitle: String
    let protectValue: String
    let protectIcon: String
    let feedTimingTitle: String
    let feedTimingValue: String
    let feedTimingIcon: String

    init(
        protectTarget: PlanBuildBeatContent.ProtectTarget?,
        feedWinMoment: PlanBuildBeatContent.FeedWinMoment?
    ) {
        protectTitle = "Block the feed"
        protectValue = protectTarget.map { "Protect \($0.title.localizedLowercase)" } ?? "Protect your time"
        protectIcon = protectTarget?.paywallIcon ?? "lock.shield.fill"
        feedTimingTitle = "Guard addictive apps"
        feedTimingValue = feedWinMoment?.title ?? "Your weakest moment"
        feedTimingIcon = feedWinMoment?.paywallIcon ?? "bell.badge.fill"
    }
}

struct PaywallPlanCardLayout: Equatable {
    let spacing: CGFloat
    let cardWidth: CGFloat
    let groupWidth: CGFloat
    let sideInset: CGFloat
    let groupOffsetX: CGFloat

    init(containerWidth: CGFloat, compact: Bool) {
        spacing = 12
        let minSideInset: CGFloat = 0
        let maxCardWidth: CGFloat = compact ? 160 : 168
        let usableWidth = max(0, containerWidth - (minSideInset * 2))
        cardWidth = max(0, min((usableWidth - spacing) / 2, maxCardWidth))
        groupWidth = (cardWidth * 2) + spacing
        sideInset = max(0, (containerWidth - groupWidth) / 2)
        groupOffsetX = 0
    }
}

private extension PlanBuildBeatContent.ProtectTarget {
    var paywallIcon: String {
        switch self {
        case .school: return "graduationcap.fill"
        case .work: return "briefcase.fill"
        case .sleep: return "bed.double.fill"
        case .creativeWork: return "paintpalette.fill"
        case .relationships: return "heart.fill"
        case .mentalClarity: return "brain.head.profile"
        }
    }
}

private extension PlanBuildBeatContent.FeedWinMoment {
    var paywallIcon: String {
        switch self {
        case .lateNight: return "moon.stars.fill"
        case .morning: return "sun.max.fill"
        case .betweenWorkOrClass: return "calendar.badge.clock"
        case .afterStress: return "bolt.heart.fill"
        case .whenBored: return "hourglass"
        case .allDay: return "iphone"
        }
    }
}

// MARK: - Design tokens

/// A single horizontal line, stroked dashed for the receipt perforation.
/// Lets the exit sheet report its intrinsic height so the detent fits the
/// content — `.medium` left a slab of dead black below the buttons.
private struct PWDashRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private enum PW {
    static let bg = AppColors.pageBgDark
    static let accent = AppColors.accent
    static let amber = AppColors.amber
    static let mint = AppColors.mint
    static let coral = AppColors.coral
    static let fg = Color.white
    static let fg2 = Color.white.opacity(0.86)
    static let fgMuted = Color.white.opacity(0.62)
    static let fg3 = Color.white.opacity(0.38)
    static let fg4 = Color.white.opacity(0.22)
    static let hairline = Color.white.opacity(0.06)
    static let closeFill = AppColors.pageBgDark.opacity(0.72)
}

private struct PaywallPlanOptionCard: View {
    let badge: String?
    let title: String
    let price: String
    let detail: String
    let compact: Bool
    let isSelected: Bool
    let action: () -> Void

    private var titleColor: Color {
        isSelected ? PW.bg.opacity(0.62) : Color.white.opacity(0.74)
    }

    private var primaryColor: Color {
        isSelected ? PW.bg : .white
    }

    private var detailColor: Color {
        isSelected ? PW.bg.opacity(0.54) : Color.white.opacity(0.54)
    }

    var body: some View {
        Button(action: action) {
            cardContent
                .background(cardBackground)
                .overlay(cardBorder)
                .overlay(alignment: .topLeading) { badgeView }
                .shadow(
                    color: isSelected ? PW.bg.opacity(0.24) : PW.bg.opacity(0.12),
                    radius: isSelected ? 16 : 8,
                    y: isSelected ? 10 : 5
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(titleColor)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PW.mint)
                }
            }

            Text(price)
                .font(.system(size: compact ? 19 : 21, weight: .black, design: .rounded))
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(detail)
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(detailColor)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 92 : 104, alignment: .leading)
        .padding(.horizontal, compact ? 13 : 14)
        .padding(.vertical, compact ? 13 : 14)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? Color.white : Color.white.opacity(0.22))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(
                isSelected ? PW.accent.opacity(0.68) : Color.white.opacity(0.22),
                lineWidth: isSelected ? 2 : 1
            )
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(PW.bg)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(PW.amber))
                .offset(x: 12, y: -12)
        }
    }
}

// MARK: - Onboarding paywall pieces

/// The three feeds from earlier in onboarding, padlocked, with Memo standing
/// guard on the headline — the product's promise in one image.
private struct PaywallUnlockHero: View {
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let apps: [(asset: String, x: CGFloat, y: CGFloat, angle: Double)] = [
        ("logo-instagram", -96, -30, -11),
        ("logo-tiktok", 0, -54, 0),
        ("logo-youtube", 96, -30, 11)
    ]

    var body: some View {
        let scale: CGFloat = compact ? 0.74 : 1
        let tile: CGFloat = 62 * scale
        ZStack(alignment: .bottom) {
            ForEach(apps.indices, id: \.self) { index in
                let app = apps[index]
                OnboardingAppIcon(asset: app.asset, size: tile)
                    .stickerOutline(2.5)
                    .overlay(alignment: .bottomTrailing) {
                        StickerIcon(kind: .padlock, size: tile * 0.28)
                            .frame(width: tile * 0.4, height: tile * 0.4)
                            .background(Circle().fill(.white))
                            .overlay(Circle().strokeBorder(ClimbColor.ink, lineWidth: 2.5))
                            .offset(x: tile * 0.14, y: tile * 0.14)
                    }
                    .rotationEffect(.degrees(app.angle))
                    .offset(x: app.x * scale, y: app.y * scale - (appeared ? 0 : 12))
                    .opacity(appeared ? 1 : 0)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            }

            // Feet on the headline: nudged below the hero's frame so Memo
            // stands on the title instead of covering the TikTok icon.
            RiveMascotView(mood: .neutral, size: 112 * scale, playbackPolicy: .continuous)
                .offset(y: 26 * scale)
                .accessibilityHidden(true)
        }
        .frame(height: 162 * scale, alignment: .bottom)
        // Memo stands on the hill's crest.
        .climbCrest(below: 21 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instagram, TikTok and YouTube, locked by Memo")
        .onAppear(perform: play)
    }

    private func play() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { appeared = true }
    }
}

/// Feature tiles drawn from the product itself instead of stock glyphs.
private struct PaywallFeatureTile: View {
    enum Kind { case block, play, rank }
    let kind: Kind
    let compact: Bool

    private var title: String {
        switch kind {
        case .block: return "Block any app"
        case .play: return "Play to unlock"
        case .rank: return "Climb the ranks"
        }
    }

    var body: some View {
        VStack(spacing: compact ? 6 : 9) {
            visual
                .frame(height: compact ? 42 : 52)
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 14)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.024, green: 0.118, blue: 0.149).opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
        .background(RoundedRectangle(cornerRadius: 19.5, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 2).padding(-2))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ClimbColor.ink).offset(y: 4))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var visual: some View {
        let unit: CGFloat = compact ? 0.82 : 1
        switch kind {
        case .block:
            ZStack {
                appTile("logo-instagram", size: 32 * unit)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -9 * unit, y: -3 * unit)
                appTile("logo-tiktok", size: 34 * unit)
                    .offset(x: 7 * unit, y: 2 * unit)
                OnboardingPadlock(isOpen: false, size: 22 * unit)
                    .offset(x: 22 * unit, y: 12 * unit)
            }
        case .play:
            TimelineView(.periodic(from: .now, by: 1.1)) { context in
                let patterns: [Set<Int>] = [[0, 4, 7], [2, 3, 8], [1, 5, 6], [0, 2, 7]]
                let lit = patterns[Int(context.date.timeIntervalSinceReferenceDate / 1.1) % patterns.count]
                let cell = 11 * unit
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { column in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(lit.contains(row * 3 + column) ? OB.accent : Color.white.opacity(0.12))
                                    .frame(width: cell, height: cell)
                                    .animation(.easeInOut(duration: 0.25), value: lit)
                            }
                        }
                    }
                }
                .padding(6 * unit)
                .background(RoundedRectangle(cornerRadius: 10 * unit, style: .continuous).fill(OB.surface))
            }
        case .rank:
            ZStack {
                StickerIcon(kind: .trophy, size: 40 * unit)
                MedalSticker(rank: 1, size: 20 * unit)
                    .offset(x: 16 * unit, y: 14 * unit)
            }
        }
    }

    private func appTile(_ asset: String, size: CGFloat) -> some View {
        OnboardingAppIcon(asset: asset, size: size)
    }
}

/// The yearly saving as a tab that breaks the card's top edge.
private struct PaywallSaveTab: View {
    let text: String
    @State private var popped = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(PW.bg)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [OB.amber, Color(red: 1.0, green: 0.62, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Capsule().strokeBorder(ClimbColor.ink, lineWidth: 2))
            .shadow(color: OB.amber.opacity(0.55), radius: 10, y: 3)
            .rotationEffect(.degrees(-3))
            .scaleEffect(popped ? 1 : 0.4)
            .opacity(popped ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.5).delay(0.9)) { popped = true }
            }
    }
}

// MARK: - PaywallView

struct PaywallView: View {
    var isHighIntent: Bool = false
    var currentStreak: Int = 0
    var todayScoreGain: Int = 0
    var isPersonalBest: Bool = false
    var gamesPlayedToday: Int = 0
    var triggerSource: String = "unknown"
    var isHardPaywall: Bool = false
    var dailyScreenTimeHours: Double = 4.72 // fallback ~4h 43m
    var onboardingAge: Int? = nil
    var onboardingGoalSummary: String = "hours back"
    var screenTimeIsEstimate: Bool = false
    var hasScreenTimeInput: Bool = true
    var protectTarget: PlanBuildBeatContent.ProtectTarget? = nil
    var feedWinMoment: PlanBuildBeatContent.FeedWinMoment? = nil
    var onConversionComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(StoreService.self) private var storeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPlan: PaywallPlan = .annual
    /// Onboarding paywall: where Memo stands, so the hill's crest meets his feet.
    @State private var climbCrestY: CGFloat?
    @State private var showCodeRedemption = false
    /// Set when the offer-code sheet opens; cleared once a redemption lands.
    @State private var awaitingOfferCode = false
    private var compactPhone: Bool { UIScreen.main.bounds.height < 700 }
    private let exitOfferRegularPriceFallback = 59.99
    private let exitOfferRegularPriceTextFallback = "$59.99"

    private var shouldShowCloseButton: Bool {
        // The onboarding paywall has no dismiss route. An X that opened a
        // different offer looked like a broken close control.
        !isHardPaywall
    }

    /// Keyed off the SELECTED PLAN, not off trial presence. There are three
    /// states, not two — annual-with-trial, annual-without, and weekly — and
    /// the old copy collapsed the middle one into weekly wording.
    private var ctaTitle: String {
        if selectedPlanHasTrial { return "Start free trial" }
        return selectedPlan == .annual ? "Continue with Yearly" : "Start Weekly Access"
    }

    private var planSubtitle: String {
        if selectedPlanHasTrial { return "Free for \(trialLabel ?? "the trial period"). Then it renews." }
        return selectedPlan == .annual
            ? "Full access to Memo Pro, billed yearly."
            : "Full access to Memo Pro, billed weekly."
    }

    /// e.g. "7 days", or nil when no usable trial exists. Resolved from
    /// StoreKit, so a returning subscriber who already consumed the trial is
    /// never promised "$0.00" and then handed a full-price sheet.
    private var trialLabel: String? { storeService.annualFreeTrialLabel }

    /// The annual SKU can have a configured trial even when this Apple account
    /// has already used it. Keep the offer visible with an eligibility qualifier
    /// instead of silently turning the annual card into a plain-price card.
    private var configuredTrialLabel: String? {
        guard let offer = storeService.annualIntroOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period.trialLengthLabel
    }

    private var annualTrialLabel: String? {
        trialLabel ?? configuredTrialLabel
    }

    /// Replaces the hardcoded `PaywallPlan.hasTrial`, which asserted a trial on
    /// the annual plan regardless of what StoreKit would actually grant.
    private var selectedPlanHasTrial: Bool {
        selectedPlan == .annual && trialLabel != nil
    }

    private var showsAnnualTrialOffer: Bool {
        selectedPlan == .annual && annualTrialLabel != nil
    }

    private var annualTrialBadge: String {
        if let trialLabel { return "\(trialLabel.uppercased()) FREE" }
        if let configuredTrialLabel { return "\(configuredTrialLabel.uppercased()) FOR ELIGIBLE" }
        return "FULL ACCESS"
    }

    private var personalizationSummary: String {
        var inputs: [String] = []
        if hasScreenTimeInput { inputs.append("your \(screenTimeSourceText.lowercased())") }
        if onboardingAge != nil { inputs.append("your age") }
        inputs.append("your \(planGoalText) goal")
        return "Built around \(inputs.joined(separator: ", "))."
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                content(
                    safeTop: proxy.safeAreaInsets.top,
                    safeBottom: proxy.safeAreaInsets.bottom,
                    height: proxy.size.height
                )
                if shouldShowCloseButton {
                    closeButton(safeTop: proxy.safeAreaInsets.top, width: proxy.size.width)
                }
                #if DEBUG
                if !ProcessInfo.processInfo.arguments.contains("--hide-dev-controls") {
                    debugSkipButton(safeTop: proxy.safeAreaInsets.top)
                }
                #endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // The hill image is scaledToFill, so as a ZStack sibling it reported
            // a width wider than the screen and dragged the whole content column
            // off-centre — badly on tall devices. As a background it can still
            // bleed visually but can no longer affect layout.
            .background {
                ZStack {
                    PW.bg
                    atmosphere
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isHardPaywall)
        .offerCodeRedemption(isPresented: $showCodeRedemption)
        .onChange(of: showCodeRedemption) { wasShowing, isShowing in
            guard wasShowing && !isShowing else { return }
            Task {
                await storeService.updateSubscriptionStatus(source: "offer_code_redemption")
                if storeService.isProUser {
                    completeOfferCodeRedemption()
                }
            }
        }
        // Apple can grant a redeemed code a beat after its sheet closes; the
        // transaction listener flips `isProUser` then, so finish from here too.
        .onChange(of: storeService.isProUser) { _, isPro in
            guard isPro, awaitingOfferCode else { return }
            completeOfferCodeRedemption()
        }
        // Purchase failures were silent — the error string was set but never
        // rendered, so a failed buy looked like a dead button.
        .alert(
            "Purchase issue",
            isPresented: Binding(
                get: { storeService.purchaseError != nil },
                set: { if !$0 { storeService.purchaseError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { storeService.purchaseError = nil }
        } message: {
            Text(storeService.purchaseError ?? "")
        }
        .onAppear {
            // Recover from a failed launch-time product load: clear any stale
            // error and re-request so the paywall is never dead on arrival.
            if storeService.products.isEmpty {
                storeService.purchaseError = nil
                Task {
                    await storeService.startIfNeeded()
                    await storeService.loadProducts()
                }
            }
            Analytics.paywallShown(
                trigger: triggerSource,
                isHighIntent: isHighIntent,
                selectedPlan: selectedPlan.analyticsName
            )
        }
    }

    // MARK: - Atmosphere

    private var atmosphere: some View {
        ZStack {
            if triggerSource == "onboarding_concise" {
                // The top of the climb: sunrise on Memo's hill.
                OnboardingClimbBackdrop(sky: .sunrise, crestY: climbCrestY)
            } else {
                Image("paywall-twilight-hill-bg")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [PW.bg.opacity(0.0), PW.bg.opacity(0.10), PW.bg.opacity(0.70), PW.bg.opacity(0.93)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private func content(safeTop: CGFloat, safeBottom: CGFloat, height: CGFloat) -> some View {
        let compact = height < 720

        if triggerSource == "onboarding_concise" {
            return AnyView(conciseOnboardingContent(safeTop: safeTop, safeBottom: safeBottom, compact: compact))
        }
        return AnyView(cutePaywallContent(safeTop: safeTop, safeBottom: safeBottom, compact: compact))
    }

    private func hardPaywallContent(
        safeTop: CGFloat,
        safeBottom: CGFloat,
        compact: Bool,
        topSpacer: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(
                height: topSpacer
            )

            personalizedPlanHeader(compact: compact)
                .padding(.bottom, compact ? 10 : 12)

            planToggle
                .frame(maxWidth: 268)
                .padding(.bottom, 10)

            hardPaywallTerms
                .padding(.bottom, 10)

            Spacer(minLength: compact ? 10 : 16)

            restoreButton
                .padding(.bottom, 8)

            footer
                .padding(.bottom, 10)

            ctaButton
                .frame(maxWidth: 340)
                .padding(.bottom, 8)

            trialPaymentNotice

            Color.clear.frame(height: max(8, safeBottom - 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
    }

    private func cutePaywallContent(
        safeTop: CGFloat,
        safeBottom: CGFloat,
        compact: Bool
    ) -> some View {
        return VStack(spacing: 0) {
            Color.clear.frame(height: max(14, safeTop + (compact ? 8 : 16)))

            Color.clear.frame(height: compact ? 14 : 30)

            readyHeadline(compact: compact)
                .padding(.bottom, compact ? 8 : 10)

            if triggerSource != "onboarding_concise" {
                researchCredibility(compact: compact)
                    .padding(.bottom, compact ? 12 : 16)
            }

            cutePlanHero(compact: compact)
                .padding(.bottom, compact ? 10 : 14)

            Spacer(minLength: compact ? 8 : 12)

            planCards(compact: compact)
                .frame(maxWidth: 360)
                .padding(.bottom, compact ? 10 : 12)

            cuteCTAButton
                .frame(maxWidth: 356)
                .padding(.bottom, 7)

            trialPaymentNotice
                .padding(.bottom, compact ? 5 : 7)

            cuteFooter
                .padding(.bottom, max(10, safeBottom - 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
    }

    /// The paywall that ends onboarding. Everything priced here comes from
    /// StoreKit: product display prices, the per-week math, the savings
    /// figure, and whether this Apple ID can actually use the annual trial.
    private func conciseOnboardingContent(
        safeTop: CGFloat,
        safeBottom: CGFloat,
        compact: Bool
    ) -> some View {
        VStack(spacing: 0) {
            GeometryReader { scrollArea in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        PaywallUnlockHero(compact: compact)
                            .frame(maxWidth: .infinity)
                            .padding(.top, compact ? 0 : 8)
                            .zIndex(1)

                        ClimbHeadline(text: conciseHeadline, size: compact ? 26 : 32)
                            .frame(maxWidth: .infinity)
                            .padding(.top, compact ? 10 : 18)
                            .animation(nil, value: selectedPlan)

                        // Short phones keep the hero and plans on one screen; the
                        // hero already shows what blocking looks like.
                        if !compact {
                            HStack(alignment: .top, spacing: 10) {
                                PaywallFeatureTile(kind: .block, compact: compact)
                                PaywallFeatureTile(kind: .play, compact: compact)
                                PaywallFeatureTile(kind: .rank, compact: compact)
                            }
                            .padding(.top, 20)
                        }

                        Spacer(minLength: compact ? 16 : 24)

                        VStack(spacing: 10) {
                            annualPlanCard(compact: compact)
                            weeklyPlanCard(compact: compact)
                        }
                        .padding(.top, 13)

                        if storeService.products.isEmpty && !storeService.isLoading {
                            HStack {
                                Text("Couldn't load prices.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(PW.fgMuted)
                                Spacer()
                                Button("Try again") {
                                    storeService.purchaseError = nil
                                    Task { await storeService.loadProducts() }
                                }
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(OB.accent)
                                .buttonStyle(.plain)
                            }
                            .frame(minHeight: 44)
                            .padding(.top, 6)
                        }

                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .frame(maxWidth: 500, minHeight: scrollArea.size.height, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: compact ? 6 : 8) {
                Text(conciseSummaryLine)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                ChunkyButton(
                    title: storeService.isLoading && !storeService.products.isEmpty ? "Opening App Store…" : conciseCTATitle,
                    systemImage: nil
                ) {
                    Task { await purchaseSelectedPlan() }
                }
                .disabled(storeService.isLoading || !conciseSelectedProductAvailable)
                .opacity(storeService.isLoading || !conciseSelectedProductAvailable ? 0.5 : 1)

                if selectedPlanHasTrial {
                    OBReassurance(text: "No payment due now")
                }

                Text(conciseDisclosure)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PW.fgMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                HStack(spacing: compact ? 16 : 22) {
                    Button("Promo code") {
                        Analytics.paywallPromoCodeTapped(trigger: triggerSource, isHighIntent: isHighIntent)
                        awaitingOfferCode = true
                        showCodeRedemption = true
                    }
                        .accessibilityHint("Redeem an Apple offer or promo code")
                    Button("Restore") {
                        Task {
                            Analytics.paywallRestoreTapped(trigger: triggerSource, isHighIntent: isHighIntent)
                            let restored = await storeService.restorePurchases()
                            Analytics.paywallRestoreCompleted(trigger: triggerSource, isHighIntent: isHighIntent, isProUser: restored)
                            if restored {
                                onConversionComplete?()
                                dismiss()
                            }
                        }
                    }
                    Link("Terms", destination: URL(string: "https://getmemoriapp.com/terms")!)
                    Link("Privacy", destination: URL(string: "https://getmemoriapp.com/privacy")!)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PW.fgMuted)
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, safeBottom > 0 ? 2 : 10)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .background(
                // The grass darkens under the purchase controls instead of a hard panel.
                LinearGradient(
                    colors: [Color(red: 0, green: 0.133, blue: 0.165).opacity(0), Color(red: 0, green: 0.133, blue: 0.165).opacity(0.92), Color(red: 0, green: 0.133, blue: 0.165)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.35)
                )
                .padding(.top, -24)
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: selectedPlan)
        .coordinateSpace(name: ClimbReporter.space)
        .environment(\.climbReporter, ClimbReporter(crest: { y in if climbCrestY != y { climbCrestY = y } }))
    }

    private func annualPlanCard(compact: Bool) -> some View {
        concisePlanCard(
            plan: .annual,
            title: "Yearly",
            highlight: trialLabel.map { "\($0) free" },
            strikePrice: conciseSavingsPercent == nil ? nil : conciseWeeklyAnnualizedPrice,
            subtitle: conciseAnnualPrice.map { "\($0) billed yearly" } ?? "Billed yearly",
            bigPrice: conciseAnnualPerWeekPrice,
            badge: conciseSavingsPercent.map { "SAVE \($0)%" },
            compact: compact
        )
    }

    private func weeklyPlanCard(compact: Bool) -> some View {
        concisePlanCard(
            plan: .weekly,
            title: "Weekly",
            highlight: nil,
            strikePrice: nil,
            subtitle: "No free trial · billed weekly",
            bigPrice: conciseWeeklyPrice,
            badge: nil,
            compact: compact
        )
    }

    /// Both plans quote a per-week price so the yearly saving is obvious at a
    /// glance; the billed amount sits underneath.
    private func concisePlanCard(
        plan: PaywallPlan,
        title: String,
        highlight: String?,
        strikePrice: String?,
        subtitle: String,
        bigPrice: String?,
        badge: String?,
        compact: Bool
    ) -> some View {
        let selected = selectedPlan == plan
        return Button { selectPlan(plan) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? ClimbColor.mint : .clear)
                    Circle()
                        .strokeBorder(selected ? ClimbColor.ink : Color.white.opacity(0.4), lineWidth: 2)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(ClimbColor.ink)
                            .transition(.scale)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(selected ? ClimbColor.ink : .white)
                    if let highlight {
                        Text(highlight)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(selected ? Color(red: 0.05, green: 0.52, blue: 0.4) : ClimbColor.mint)
                    }
                    HStack(spacing: 5) {
                        if let strikePrice {
                            Text(strikePrice)
                                .strikethrough(true, color: OB.coral)
                                .foregroundStyle(selected ? ClimbColor.ink.opacity(0.5) : PW.fgMuted.opacity(0.8))
                        }
                        Text(subtitle)
                            .foregroundStyle(selected ? ClimbColor.ink.opacity(0.65) : PW.fgMuted)
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 0) {
                    if let bigPrice {
                        Text(bigPrice)
                            .font(.system(size: compact ? 22 : 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(selected ? ClimbColor.ink : .white)
                            .monospacedDigit()
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 60, height: 22)
                            .accessibilityLabel("Loading price")
                    }
                    Text("per week")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? ClimbColor.ink.opacity(0.6) : PW.fgMuted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.top, badge == nil ? 12 : 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 66 : 78)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? Color.white : Color(red: 0.024, green: 0.118, blue: 0.149).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ClimbColor.ink, lineWidth: 2.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 21.5, style: .continuous)
                    .strokeBorder(selected ? ClimbColor.mint : Color.white.opacity(0.35), lineWidth: selected ? 3 : 2)
                    .padding(selected ? -3 : -2)
            )
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ClimbColor.ink).offset(y: 5))
            .overlay(alignment: .topLeading) {
                if let badge {
                    PaywallSaveTab(text: badge)
                        .offset(x: 16, y: -13)
                }
            }
            .shadow(color: selected ? ClimbColor.mint.opacity(0.35) : .clear, radius: 16, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var conciseWeeklyAnnualizedPrice: String? {
        guard let weekly = storeService.products.first(where: { $0.id == StoreService.weeklyUltraProductID }) else { return nil }
        return weekly.priceFormatStyle.format(weekly.price * Decimal(52))
    }

    private var conciseSavingsPercent: Int? {
        guard let weekly = storeService.products.first(where: { $0.id == StoreService.weeklyUltraProductID }),
              let annual = storeService.products.first(where: { $0.id == StoreService.annualUltraProductID }) else { return nil }
        let yearlyAtWeeklyRate = NSDecimalNumber(decimal: weekly.price).doubleValue * 52
        guard yearlyAtWeeklyRate > 0 else { return nil }
        let fraction = 1 - NSDecimalNumber(decimal: annual.price).doubleValue / yearlyAtWeeklyRate
        let percent = Int((fraction * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    private var conciseAnnualPerWeekPrice: String? {
        guard let annual = storeService.products.first(where: { $0.id == StoreService.annualUltraProductID }) else { return nil }
        return annual.priceFormatStyle.format(annual.price / Decimal(52))
    }

    private var conciseAnnualPrice: String? {
        storeService.products.first(where: { $0.id == StoreService.annualUltraProductID })?.displayPrice
    }

    private var conciseWeeklyPrice: String? {
        storeService.products.first(where: { $0.id == StoreService.weeklyUltraProductID })?.displayPrice
    }

    private var conciseSelectedProductAvailable: Bool {
        selectedPlan == .annual ? conciseAnnualPrice != nil : conciseWeeklyPrice != nil
    }

    private var conciseHeadline: String {
        if selectedPlanHasTrial, let trialLabel { return "Try Memo Pro free for \(trialLabel)." }
        return selectedPlan == .annual ? "Keep the feed locked all year." : "Keep the feed locked, week by week."
    }

    private var conciseSummaryLine: String {
        if selectedPlanHasTrial, let trialLabel, let price = conciseAnnualPrice {
            return "\(trialLabel) free, then \(price)/year"
        }
        switch selectedPlan {
        case .annual: return conciseAnnualPrice.map { "\($0) per year" } ?? "Loading prices…"
        case .weekly: return conciseWeeklyPrice.map { "\($0) per week" } ?? "Loading prices…"
        }
    }

    private var conciseCTATitle: String {
        if selectedPlanHasTrial { return "Start free trial" }
        return selectedPlan == .annual ? "Subscribe yearly" : "Subscribe weekly"
    }

    /// Auto-renew terms, stated with the live price for the selected plan.
    private var conciseDisclosure: String {
        let cancel = "Cancel in Settings › Apple ID › Subscriptions"
        if selectedPlanHasTrial {
            let start = storeService.annualFreeTrialDays
                .flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
                .map { " from \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? " after the trial"
            return "Renews at \(conciseAnnualPrice ?? "the yearly price")/year\(start) until canceled. \(cancel) at least 24 hours before the trial ends to avoid the charge."
        }
        if selectedPlan == .annual {
            return "\(conciseAnnualPrice ?? "The yearly price") charged today, then every year until canceled. \(cancel) at least 24 hours before renewal."
        }
        return "\(conciseWeeklyPrice ?? "The weekly price") charged today, then every week until canceled. \(cancel) at least 24 hours before renewal."
    }

    private var screenTimeReceiptValue: String {
        let clamped = max(0, dailyScreenTimeHours)
        let totalMinutes = Int((clamped * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours <= 0 { return "\(minutes)m/day" }
        if minutes == 0 { return "\(hours)h/day" }
        return "\(hours)h \(minutes)m/day"
    }

    private var planAgeText: String {
        if let onboardingAge { return "\(onboardingAge)" }
        return "25"
    }

    private var planGoalText: String {
        onboardingGoalSummary.isEmpty ? "hours back" : onboardingGoalSummary
    }

    private var screenTimeSourceText: String {
        screenTimeIsEstimate ? "estimate" : "Screen Time"
    }

    private var personalizationContent: PaywallPersonalizationContent {
        PaywallPersonalizationContent(protectTarget: protectTarget, feedWinMoment: feedWinMoment)
    }

    private var regularAnnualPriceText: String {
        productDisplayPrice(for: StoreService.annualUltraProductID, fallback: exitOfferRegularPriceTextFallback)
    }

    private var regularAnnualMonthlyText: String {
        monthlyPriceText(for: StoreService.annualUltraProductID, fallbackAnnualPrice: exitOfferRegularPriceFallback)
    }

    private var annualWeeklyText: String {
        weeklyPriceText(for: StoreService.annualUltraProductID, fallbackAnnualPrice: exitOfferRegularPriceFallback)
    }

    private var weeklyDisplayPriceText: String {
        productDisplayPrice(for: StoreService.weeklyUltraProductID, fallback: "$4.99")
    }

    private func selectPlan(_ plan: PaywallPlan) {
        if selectedPlan != plan {
            Analytics.paywallPlanSelected(
                plan: plan.analyticsName,
                productID: plan.productID,
                trigger: triggerSource,
                isHighIntent: isHighIntent
            )
        }
        selectedPlan = plan
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func readyHeadline(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 7) {
            Text(triggerSource == "onboarding_concise"
                 ? (selectedPlanHasTrial ? "Your Memo trial\nstarts here" : "Your Memo plan\nstarts here")
                 : "Your personalized\nplan is ready")
                .font(.system(size: compact ? 29 : 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Text(heroLine)
                .font(.brand(size: compact ? 26 : 30, weight: .heavy))
                .foregroundStyle(selectedPlanHasTrial ? PW.mint : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)

            Text(heroSubline)
                .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func cutePlanHero(compact: Bool) -> some View {
        Image("mascot-unlocked")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: compact ? 130 : 160, height: compact ? 130 : 160)
            .shadow(color: PW.accent.opacity(0.26), radius: 22, y: 10)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var heroLine: String {
        if selectedPlan == .annual, let annualTrialLabel { return "Annual includes \(annualTrialLabel) free" }
        return selectedPlan == .annual ? "\(regularAnnualPriceText) a year" : "\(weeklyDisplayPriceText) a week"
    }

    private var heroSubline: String {
        if selectedPlanHasTrial {
            return "Then \(regularAnnualPriceText)/year. Cancel before the trial ends to avoid the annual charge."
        }
        if selectedPlan == .annual, annualTrialLabel != nil {
            return "For eligible new subscribers. Otherwise \(regularAnnualPriceText)/year."
        }
        return selectedPlan == .annual
            ? "Billed yearly. Cancel anytime in the App Store."
            : "Billed weekly. Cancel anytime in the App Store."
    }

    private func miniPlanCard<Content: View>(
        angle: Double,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        compact: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: compact ? 122 : 138, height: compact ? 124 : 142)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.78), lineWidth: 1)
            )
            .shadow(color: PW.bg.opacity(0.18), radius: 14, y: 8)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }

    private func mainPlanCard(compact: Bool) -> some View {
        // An itemized receipt, not a feature card. Memo's whole funnel is built
        // on receipts — "Private Screen Time receipt", the life receipt, the
        // ledger rows on the trial bridge — so the plan reads as one too:
        // labels left, values right, perforated rules, and a total line.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMO PLAN")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(PW.accent)

                Spacer(minLength: 8)

                Text(selectedPlan == .annual ? annualTrialBadge : "WEEKLY")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(selectedPlan == .annual && selectedPlanHasTrial ? PW.mint : PW.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.bottom, compact ? 11 : 13)

            receiptPerforation

            if hasScreenTimeInput {
                receiptLine("Your screen time", screenTimeReceiptValue, compact: compact)
            }
            receiptLine("Brain training", "10 games", compact: compact)
            if triggerSource != "onboarding_concise" {
                receiptLine("Protecting", protectTarget?.title ?? "Your time", compact: compact)
                receiptLine("Weakest moment", feedWinMoment?.title ?? "To be discovered", compact: compact)
            } else {
                receiptLine("Unlock loop", "Block · Play · Unlock", compact: compact)
            }

            receiptPerforation

            HStack(alignment: .firstTextBaseline) {
                Text("DUE TODAY")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(PW.bg.opacity(0.52))

                Spacer(minLength: 8)

                Text(dueTodayText)
                    .font(.brand(size: compact ? 25 : 29, weight: .heavy))
                    .foregroundStyle(selectedPlanHasTrial ? PW.mint : PW.bg)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, compact ? 10 : 12)
        }
        .padding(.horizontal, compact ? 18 : 20)
        .padding(.top, compact ? 34 : 40)
        .padding(.bottom, compact ? 15 : 17)
        .frame(maxWidth: compact ? 300 : 320)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PW.accent.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: PW.bg.opacity(0.22), radius: 18, y: 12)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, compact ? 26 : 32)
        .accessibilityElement(children: .combine)
    }

    /// What the card charges right now — "$0.00" is the whole pitch when a
    /// trial is live, and the honest price when it isn't.
    private var dueTodayText: String {
        if selectedPlanHasTrial { return "$0.00" }
        return selectedPlan == .annual ? regularAnnualPriceText : weeklyDisplayPriceText
    }

    private var receiptPerforation: some View {
        PWDashRule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .foregroundStyle(PW.bg.opacity(0.20))
            .frame(height: 1)
    }

    private func receiptLine(_ label: String, _ value: String, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.brand(size: compact ? 13 : 14, weight: .medium))
                .foregroundStyle(PW.bg.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 6)

            Text(value)
                .font(.brand(size: compact ? 14 : 15, weight: .heavy))
                .foregroundStyle(PW.bg)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, compact ? 5 : 6)
    }

    private func planCardMiniContent(
        title: String,
        value: String,
        icon: String,
        color: Color,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: compact ? 17 : 19, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.13)))

            Spacer(minLength: 2)

            Text(title)
                .font(.system(size: compact ? 9 : 10, weight: .black, design: .rounded))
                .foregroundStyle(PW.bg.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(value)
                .font(.system(size: compact ? 14 : 16, weight: .black, design: .rounded))
                .foregroundStyle(PW.bg)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(12)
    }

    private func planHeroRow(
        icon: String,
        title: String,
        value: String,
        color: Color,
        compact: Bool
    ) -> some View {
        // Was 8pt/11pt with a 0.72 floor — as small as 5.8pt, well under the
        // 11pt HIG minimum, on the one card that states what you're buying.
        HStack(spacing: compact ? 9 : 10) {
            Image(systemName: icon)
                .font(.system(size: compact ? 12 : 13, weight: .black))
                .foregroundStyle(color)
                .frame(width: compact ? 26 : 28, height: compact ? 26 : 28)
                .background(Circle().fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .black, design: .rounded))
                    .foregroundStyle(PW.bg.opacity(0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(value)
                    .font(.system(size: compact ? 14 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(PW.bg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
    }

    private func planCards(compact: Bool) -> some View {
        GeometryReader { proxy in
            let layout = PaywallPlanCardLayout(containerWidth: proxy.size.width, compact: compact)

            HStack(spacing: layout.spacing) {
                // The trial has to live on the card the user actually taps.
                // It used to appear only on the hero card above, so the
                // selected plan read as a flat yearly price.
                purchasePlanCard(
                    plan: .annual,
                    badge: trialLabel.map { "\($0.uppercased()) FREE" }
                        ?? configuredTrialLabel.map { "\($0.uppercased()) FOR ELIGIBLE" }
                        ?? "BEST VALUE",
                    title: "Yearly",
                    price: "\(regularAnnualPriceText)/year",
                    detail: annualPlanDetail,
                    compact: compact
                )
                .frame(width: layout.cardWidth)

                purchasePlanCard(
                    plan: .weekly,
                    badge: nil,
                    title: "Weekly",
                    price: "\(weeklyDisplayPriceText)/wk",
                    detail: "Billed weekly",
                    compact: compact
                )
                .frame(width: layout.cardWidth)
            }
            .frame(width: layout.groupWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: layout.groupOffsetX)
        }
        .frame(height: compact ? 116 : 138)
    }

    private var annualPlanDetail: String {
        if let trialLabel {
            return "Free \(trialLabel), then \(annualWeeklyText)"
        }
        if annualTrialLabel != nil {
            return "\(annualTrialLabel ?? "Free trial") for eligible new subscribers"
        }
        return "\(annualWeeklyText) billed yearly"
    }

    private func purchasePlanCard(
        plan: PaywallPlan,
        badge: String?,
        title: String,
        price: String,
        detail: String,
        compact: Bool
    ) -> some View {
        PaywallPlanOptionCard(
            badge: badge,
            title: title,
            price: price,
            detail: detail,
            compact: compact,
            isSelected: selectedPlan == plan,
            action: { selectPlan(plan) }
        )
    }

    private var cuteCTAButton: some View {
        Button {
            Task { await purchaseSelectedPlan() }
        } label: {
            HStack(spacing: 10) {
                Text(storeService.isLoading ? "Opening…" : ctaTitle)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .black))
            }
            .foregroundStyle(PW.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            )
            .shadow(color: PW.bg.opacity(0.30), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(storeService.isLoading)
        .opacity(storeService.isLoading ? 0.75 : 1)
    }

    private var cuteFooter: some View {
        HStack(spacing: 8) {
            Text("No ads. No data sold.")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: 3)

            Button {
                Task {
                    Analytics.paywallRestoreTapped(trigger: triggerSource, isHighIntent: isHighIntent)
                    let restored = await storeService.restorePurchases()
                    Analytics.paywallRestoreCompleted(
                        trigger: triggerSource,
                        isHighIntent: isHighIntent,
                        isProUser: restored
                    )
                    if restored {
                        dismiss()
                    }
                }
            } label: {
                Text("Restore")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .underline()
            }
            .buttonStyle(.plain)

            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: 3)

            Button {
                Analytics.paywallPromoCodeTapped(trigger: triggerSource, isHighIntent: isHighIntent)
                awaitingOfferCode = true
                showCodeRedemption = true
            } label: {
                Text("Promo code")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    private func paidNotFarmedHeader(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: compact ? 9 : 11) {
                Text("PAID, NOT FARMED")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(PW.amber)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Pay for Memo\nwith money,")
                        .font(.system(size: compact ? 28 : 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(PW.fg)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("not your attention.")
                        .font(.system(size: compact ? 28 : 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(PW.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text("Big Tech profits when you lose focus. Memo profits when you get it back.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PW.fgMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("mascot-unlocked")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 74 : 86, height: compact ? 74 : 86)
                .shadow(color: PW.accent.opacity(0.26), radius: 18, y: 8)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 360)
    }

    private func personalizedPlanHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your counterattack\nis ready.")
                        .font(.system(size: compact ? 30 : 33, weight: .black, design: .rounded))
                        .foregroundStyle(PW.fg)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(personalizationSummary)
                        .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PW.fgMuted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("mascot-unlocked")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 64 : 72, height: compact ? 64 : 72)
                    .shadow(color: PW.accent.opacity(0.24), radius: 16, y: 8)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MEMO PLAN")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.7)
                        .foregroundStyle(PW.accent)

                    Spacer()

                Text(selectedPlanHasTrial ? "\(trialLabel ?? "Trial") $0" : (selectedPlan == .annual ? "YEARLY" : "WEEKLY"))
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(selectedPlanHasTrial ? PW.mint : PW.amber)
                        .lineLimit(1)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    if let onboardingAge {
                        planProofChip(label: "AGE", value: "\(onboardingAge)", color: PW.accent)
                    }
                    if hasScreenTimeInput {
                        planProofChip(label: screenTimeSourceText.uppercased(), value: screenTimeReceiptValue, color: PW.coral)
                    }
                    planProofChip(label: "GOAL", value: planGoalText, color: PW.mint)
                    planProofChip(label: "TRAINING", value: "10 games", color: PW.amber)
                }

                Rectangle()
                    .fill(PW.hairline)
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 10) {
                    Text("Block the feed first.")
                        .font(.system(size: compact ? 14 : 15, weight: .black, design: .rounded))
                        .foregroundStyle(PW.fg)

                    Text("Then one quick brain rep earns a short unlock window.")
                        .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PW.fgMuted)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 13 : 15)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.040))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PW.accent.opacity(0.16), lineWidth: 1)
            )
        }
        .frame(maxWidth: 360)
        .accessibilityElement(children: .combine)
    }

    private func planProofChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(PW.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    private func paywallReceipt(compact: Bool) -> some View {
        let memoCost: String
        if selectedPlan == .annual {
            memoCost = regularAnnualMonthlyText
        } else {
            memoCost = "\(weeklyDisplayPriceText)/week"
        }

        return VStack(spacing: 0) {
            if hasScreenTimeInput {
                receiptRow(label: "Your daily screen time", value: screenTimeReceiptValue, color: PW.coral, compact: compact)
                receiptDivider
            }
            receiptRow(label: "Estimated ad value", value: "~$200/yr", color: PW.coral, compact: compact)
            receiptDivider
            receiptRow(label: "Memo costs", value: memoCost, color: PW.mint, compact: compact)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 10 : 12)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var receiptDivider: some View {
        Rectangle()
            .fill(PW.hairline)
            .frame(height: 1)
    }

    private func receiptRow(label: String, value: String, color: Color, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PW.fg3)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: compact ? 14 : 15, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, compact ? 8 : 9)
    }

    private var restoreButton: some View {
        return Button {
            Task {
                Analytics.paywallRestoreTapped(trigger: triggerSource, isHighIntent: isHighIntent)
                let restored = await storeService.restorePurchases()
                Analytics.paywallRestoreCompleted(
                    trigger: triggerSource,
                    isHighIntent: isHighIntent,
                    isProUser: restored
                )
                if restored {
                    dismiss()
                }
            }
        } label: {
            Text("Restore purchases")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PW.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero

    private func paywallHero(compact: Bool) -> some View {
        ZStack {
            heroLightField(compact: compact)

            Image("mascot-unlocked")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 158 : 184, height: compact ? 158 : 184)
                .shadow(color: PW.accent.opacity(0.30), radius: 24, y: 12)
                .shadow(color: Color.black.opacity(0.34), radius: 18, y: 10)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 164 : 188)
        .accessibilityHidden(true)
    }

    private func heroLightField(compact: Bool) -> some View {
        ZStack {
            Circle()
                .fill(AppColors.indigo.opacity(0.15))
                .frame(width: compact ? 210 : 242, height: compact ? 210 : 242)
                .blur(radius: 26)

            Ellipse()
                .fill(PW.accent.opacity(0.22))
                .frame(width: compact ? 230 : 272, height: compact ? 120 : 142)
                .blur(radius: 34)
                .offset(y: compact ? 8 : 10)

            Ellipse()
                .fill(AppColors.periwinkle.opacity(0.12))
                .frame(width: compact ? 170 : 202, height: compact ? 84 : 98)
                .blur(radius: 26)
                .offset(y: compact ? -18 : -22)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.periwinkle.opacity(0.16),
                            PW.accent.opacity(0.08),
                            PW.bg.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: compact ? 92 : 108
                    )
                )
                .frame(width: compact ? 168 : 196, height: compact ? 168 : 196)

            Ellipse()
                .fill(PW.accent.opacity(0.16))
                .frame(width: compact ? 142 : 168, height: compact ? 22 : 26)
                .blur(radius: 14)
                .offset(y: compact ? 66 : 78)
        }
    }

    private var headline: some View {
        Text(selectedPlanHasTrial ? "How your trial works" : "How your plan works")
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(PW.fg)
            .multilineTextAlignment(.center)
            .kerning(-0.4)
            .minimumScaleFactor(0.88)
            .lineLimit(1)
    }

    private var trialTerms: some View {
        Text(trialTermsText)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(PW.fgMuted)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }

    private var trialTermsText: String {
        if selectedPlanHasTrial {
            return "Free for \(trialLabel ?? "the trial period"), then \(regularAnnualPriceText)/year."
        }
        return selectedPlan == .annual
            ? "\(regularAnnualPriceText)/year. Cancel anytime."
            : "\(weeklyDisplayPriceText)/week. Cancel anytime."
    }

    // MARK: - Research Proof

    private func researchCredibility(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 8) {
            Text("Built from research from Stanford, Michigan, and UNC.")
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(PW.fgMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                researchLogo("logo-stanford-emblem", label: "Stanford research")
                researchLogo("logo-umich-emblem", label: "University of Michigan research")
                researchLogo("logo-unc-emblem", label: "UNC research")
            }
        }
        .frame(maxWidth: 300)
        .accessibilityElement(children: .combine)
    }

    private func methodChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(PW.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(PW.accent.opacity(0.10)))
            .overlay(Capsule().stroke(PW.accent.opacity(0.18), lineWidth: 1))
    }

    private func researchLogo(_ imageName: String, label: String) -> some View {
        Image(imageName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 20)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel(label)
    }

    // MARK: - Plan Toggle

    private var planToggle: some View {
        HStack(spacing: 0) {
            planSegment(.annual, label: "Annual")
            planSegment(.weekly, label: "Weekly")
        }
        .padding(3)
        .background(Color.white.opacity(0.035), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func planSegment(_ plan: PaywallPlan, label: String) -> some View {
        let selected = selectedPlan == plan
        return Button {
            selectPlan(plan)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? PW.fg : PW.fgMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? PW.accent : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Trial Timeline

    private func trialTimeline(compact: Bool) -> some View {
        VStack(spacing: compact ? 20 : 25) {
            trialStep(
                icon: "lock.open.fill",
                title: "Today",
                body: "Unlock every game and guard every target.",
                compact: compact
            )
            trialStep(
                icon: selectedPlanHasTrial ? "bell.fill" : "xmark.circle.fill",
                title: selectedPlanHasTrial && (storeService.annualFreeTrialDays ?? 0) > 2 ? "2 days before end" : "Anytime",
                body: selectedPlanHasTrial
                    ? ((storeService.annualFreeTrialDays ?? 0) > 2
                        ? "If notifications are on, Memo can send one reminder."
                        : "Cancel in the App Store before the trial ends.")
                    : "Cancel in the App Store whenever you want.",
                compact: compact
            )
            trialStep(
                icon: "creditcard.fill",
                title: selectedPlanHasTrial ? "After \(trialLabel ?? "trial")" : (selectedPlan == .annual ? "Yearly" : "Every week"),
                body: selectedPlan == .annual
                    ? "Your annual plan renews at \(regularAnnualPriceText) unless canceled."
                    : "Your weekly plan renews at \(weeklyDisplayPriceText) unless canceled.",
                compact: compact
            )
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 2)
                .padding(.leading, compact ? 21 : 22)
                .padding(.vertical, compact ? 25 : 27)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: 340)
    }

    private func trialStep(icon: String, title: String, body: String, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 16 : 18) {
            ZStack {
                Circle()
                    .fill(PW.accent)
                    .frame(width: compact ? 44 : 46, height: compact ? 44 : 46)

                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 17, weight: .bold))
                    .foregroundStyle(PW.fg)
            }
            .zIndex(1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(PW.fg)

                Text(body)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PW.fgMuted)
                    .lineSpacing(1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, compact ? 4 : 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            Task { await purchaseSelectedPlan() }
        } label: {
            Text(storeService.isLoading ? "Opening…" : ctaTitle)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(PW.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: PW.accent.opacity(0.30), radius: 28, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(storeService.isLoading)
        .opacity(storeService.isLoading ? 0.75 : 1)
    }

    private var trialPaymentNotice: some View {
        Text(trialPaymentNoticeText)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(showsAnnualTrialOffer ? PW.fgMuted : .clear)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 16)
            .accessibilityHidden(!showsAnnualTrialOffer)
    }

    private var trialPaymentNoticeText: String {
        if selectedPlanHasTrial {
            return "No payment today. \(regularAnnualPriceText)/year after \(trialLabel ?? "the trial")."
        }
        if selectedPlan == .annual, annualTrialLabel != nil {
            return "\(annualTrialLabel ?? "Free trial") for eligible new subscribers."
        }
        return " "
    }

    private var hardPaywallTerms: some View {
        Text(hardPaywallTermsText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(PW.fgMuted)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.84)
            .frame(maxWidth: 300)
    }

    private var hardPaywallTermsText: String {
        if selectedPlanHasTrial {
            let reminder = (storeService.annualFreeTrialDays ?? 0) > 2
                ? " If notifications are on, Memo can remind you 2 days before."
                : ""
            return "Free for \(trialLabel ?? "the trial period"), then \(regularAnnualPriceText)/year.\(reminder)"
        }
        if showsAnnualTrialOffer {
            return "\(annualTrialLabel ?? "Free trial") for eligible new subscribers; otherwise \(regularAnnualPriceText)/year."
        }
        return selectedPlan == .annual
            ? "\(regularAnnualPriceText)/year. Cancel anytime in the App Store."
            : "Weekly access. Cancel anytime in the App Store."
    }

    // MARK: - Footer

    private var footer: some View {
        Text(selectedPlanHasTrial
             ? "Paid by members. Not by surveillance. Free for \(trialLabel ?? "the trial period"), then \(regularAnnualPriceText)/year."
             : "Paid by members. Not by surveillance. Cancel anytime in the App Store.")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PW.fg3)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
    }

    #if DEBUG
    /// Dev-only bypass — sandbox purchases can't be exercised without a live
    /// Paid Apps agreement, so this fakes a conversion to test everything
    /// downstream. Compiled out of release builds entirely.
    private func debugSkipButton(safeTop: CGFloat) -> some View {
        Button {
            storeService.isProUser = true
            onConversionComplete?()
            dismiss()
        } label: {
            Text("DEV SKIP")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, min(max(12, safeTop + 8), 68))
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #endif

    // MARK: - Close Button

    private func closeButton(safeTop: CGFloat, width: CGFloat) -> some View {
        let cappedTopPadding = min(max(12, safeTop + 8), 68)
        let cappedTapRegionHeight = min(max(74, safeTop + 62), 124)

        return Button {
            Analytics.paywallDismissed(trigger: triggerSource, selectedPlan: selectedPlan.analyticsName, isHighIntent: isHighIntent)
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(PW.closeFill)
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .frame(width: 34, height: 34)

                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PW.fg)
            }
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close paywall")
        .padding(.top, cappedTopPadding)
        .padding(.trailing, 22)
        .frame(width: width, height: cappedTapRegionHeight, alignment: .topTrailing)
    }

    private func completeOfferCodeRedemption() {
        guard awaitingOfferCode else { return }
        awaitingOfferCode = false
        Analytics.paywallPromoCodeRedeemed(trigger: triggerSource, isHighIntent: isHighIntent)
        onConversionComplete?()
        dismiss()
    }

    // MARK: - Purchase

    private func purchaseSelectedPlan() async {
        await purchase(productID: selectedPlan.productID, plan: selectedPlan.analyticsName, isExitOffer: false)
    }

    private func productPrice(for productID: String, fallback: Double) -> Double {
        guard let product = storeService.products.first(where: { $0.id == productID }) else {
            return fallback
        }
        return NSDecimalNumber(decimal: product.price).doubleValue
    }

    private func productDisplayPrice(for productID: String, fallback: String) -> String {
        storeService.products.first(where: { $0.id == productID })?.displayPrice ?? fallback
    }

    private func monthlyPriceText(for productID: String, fallbackAnnualPrice: Double) -> String {
        let annualPrice = productPrice(for: productID, fallback: fallbackAnnualPrice)
        return String(format: "$%.2f/mo", annualPrice / 12.0)
    }

    private func weeklyPriceText(for productID: String, fallbackAnnualPrice: Double) -> String {
        let annualPrice = productPrice(for: productID, fallback: fallbackAnnualPrice)
        return String(format: "$%.2f/week", annualPrice / 52.0)
    }

    private func purchase(productID: String, plan: String, isExitOffer: Bool) async {
        Analytics.paywallCTATapped(
            plan: plan,
            productID: productID,
            trigger: triggerSource,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        )
        if let product = storeService.products.first(where: { $0.id == productID }) {
            await completePurchase(product, productID: productID, plan: plan, isExitOffer: isExitOffer)
        } else {
            await storeService.loadProducts()
            if let product = storeService.products.first(where: { $0.id == productID }) {
                await completePurchase(product, productID: productID, plan: plan, isExitOffer: isExitOffer)
            } else {
                storeService.purchaseError = "This offer is not ready yet."
                Analytics.paywallProductUnavailable(
                    productID: productID,
                    trigger: triggerSource,
                    isHighIntent: isHighIntent,
                    isExitOffer: isExitOffer
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func completePurchase(_ product: Product, productID: String, plan: String, isExitOffer: Bool) async {
        Analytics.paywallPurchaseStarted(
            plan: plan,
            productID: productID,
            trigger: triggerSource,
            isHighIntent: isHighIntent,
            isExitOffer: isExitOffer
        )
        // Snapshot before buying: the purchase itself consumes eligibility.
        let trialDaysAtPurchase = storeService.annualFreeTrialDays
        let outcome = await storeService.purchase(product)
        let price = NSDecimalNumber(decimal: product.price).doubleValue
        switch outcome {
        case .success:
            guard storeService.isProUser else {
                Analytics.paywallPurchaseFailed(
                    plan: plan,
                    productID: productID,
                    trigger: triggerSource,
                    isHighIntent: isHighIntent,
                    isExitOffer: isExitOffer,
                    reason: "purchase_finished_without_active_entitlement"
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            Analytics.paywallConverted(
                plan: plan,
                price: price,
                trigger: triggerSource,
                productID: productID,
                isHighIntent: isHighIntent,
                isExitOffer: isExitOffer
            )
            // Was: any annual purchase counted as a trial start. That logged
            // trial_started for full-price buys by trial-ineligible users.
            let hasTrial = productID == StoreService.annualUltraProductID
                && !isExitOffer
                && trialDaysAtPurchase != nil
            Analytics.subscriptionStarted(
                plan: plan,
                productID: productID,
                conversionKind: subscriptionConversionKind(for: productID, isExitOffer: isExitOffer),
                trigger: triggerSource,
                isHighIntent: isHighIntent,
                isExitOffer: isExitOffer,
                hasTrial: hasTrial,
                price: price
            )
            // Only schedule after a verified trial purchase, using StoreKit's
            // subscription expiration instead of an approximate calendar date.
            if productID == StoreService.annualUltraProductID, trialDaysAtPurchase != nil {
                if let endDate = await storeService.currentEntitlementExpirationDate(for: productID) {
                    NotificationService.shared.recordTrialStarted(endDate: endDate)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            SoundService.shared.playComplete()
            onConversionComplete?()
            dismiss()
        case .userCancelled:
            Analytics.paywallPurchaseCancelled(
                plan: plan,
                productID: productID,
                trigger: triggerSource,
                isHighIntent: isHighIntent,
                isExitOffer: isExitOffer
            )
        case .pending:
            Analytics.paywallPurchasePending(
                plan: plan,
                productID: productID,
                trigger: triggerSource,
                isHighIntent: isHighIntent,
                isExitOffer: isExitOffer
            )
        case .failed(let reason):
            Analytics.paywallPurchaseFailed(
                plan: plan,
                productID: productID,
                trigger: triggerSource,
                isHighIntent: isHighIntent,
                isExitOffer: isExitOffer,
                reason: reason
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func subscriptionConversionKind(for productID: String, isExitOffer: Bool) -> String {
        if productID == StoreService.annualUltraExitOfferProductID || isExitOffer {
            return "founder_forever"
        }
        if productID == StoreService.annualUltraProductID {
            return "annual_trial"
        }
        if productID == StoreService.weeklyUltraProductID {
            return "weekly_no_trial"
        }
        return Analytics.paywallPlanName(for: productID)
    }
}

// MARK: - Preview

#Preview("Paywall") {
    PaywallView(isHighIntent: true, triggerSource: "preview")
        .environment(StoreService(loadProductsOnInit: false))
}

#Preview("Onboarding Hard Paywall") {
    PaywallView(
        isHighIntent: true,
        triggerSource: "onboarding_personalized_plan",
        isHardPaywall: true,
        dailyScreenTimeHours: 4.72,
        onboardingAge: 25,
        onboardingGoalSummary: "hours back",
        screenTimeIsEstimate: true,
        protectTarget: .school,
        feedWinMoment: .lateNight
    )
    .environment(StoreService(loadProductsOnInit: false))
}

#if DEBUG
@MainActor
struct MemoCutePaywallPreviewView: View {
    @State private var selectedPlan: PaywallPlan = .annual
    /// Onboarding paywall: where Memo stands, so the hill's crest meets his feet.
    @State private var climbCrestY: CGFloat?
    private let screenTimeReceiptValue = "4h 43m"

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 720

            ZStack {
                atmosphere

                VStack(spacing: 0) {
                    Color.clear.frame(height: min(max(50, proxy.safeAreaInsets.top + 8), 80))

                    Color.clear.frame(height: compact ? 34 : 42)

                    readyHeadline(compact: compact)
                        .padding(.bottom, compact ? 9 : 11)

                    researchCredibility(compact: compact)
                        .padding(.bottom, compact ? 10 : 14)

                    planHero(compact: compact)

                    Spacer(minLength: compact ? 8 : 12)

                    planCards(compact: compact)
                        .frame(maxWidth: 360)
                        .padding(.bottom, compact ? 10 : 12)

                    ctaButton
                        .frame(maxWidth: 356)
                        .padding(.bottom, 7)

                    trialNote
                        .padding(.bottom, compact ? 5 : 7)

                    footer
                        .padding(.bottom, max(10, proxy.safeAreaInsets.bottom - 8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 22)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
    }

    private var atmosphere: some View {
        ZStack {
            Image("paywall-twilight-hill-bg")
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    PW.bg.opacity(0.0),
                    PW.bg.opacity(0.10),
                    PW.bg.opacity(0.70),
                    PW.bg.opacity(0.93)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    PW.bg.opacity(0.20),
                    PW.bg.opacity(0.0),
                    PW.bg.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private func readyHeadline(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 7) {
            Text("Your personalized\nplan is ready")
                .font(.system(size: compact ? 29 : 34, weight: .black, design: .rounded))
                .foregroundStyle(PW.fg)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Text(selectedPlan == .annual ? "Get unlimited access to Memo Pro." : "Start weekly access to Memo Pro.")
                .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PW.fg2.opacity(0.84))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
        }
        .accessibilityElement(children: .combine)
    }

    private func researchCredibility(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 8) {
            Text("Built from research from Stanford, Michigan, and UNC.")
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(PW.fgMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                researchLogo("logo-stanford-emblem", label: "Stanford research")
                researchLogo("logo-umich-emblem", label: "University of Michigan research")
                researchLogo("logo-unc-emblem", label: "UNC research")
            }
        }
        .frame(maxWidth: 300)
        .accessibilityElement(children: .combine)
    }

    private func researchLogo(_ imageName: String, label: String) -> some View {
        Image(imageName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 20)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PW.fg.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PW.fg.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel(label)
    }

    private func planHero(compact: Bool) -> some View {
        ZStack {
            miniPlanCard(angle: 0, x: compact ? -90 : -106, y: compact ? 13 : 17, scale: 0.82, compact: compact) {
                miniCardContent(title: "Screen Time", value: "4h 43m/day", icon: "chart.bar.fill", color: PW.coral, compact: compact)
            }

            miniPlanCard(angle: 0, x: compact ? 90 : 106, y: compact ? 13 : 17, scale: 0.82, compact: compact) {
                miniCardContent(title: "Focus Guard", value: "Whole feed", icon: "lock.fill", color: PW.accent, compact: compact)
            }

            mainPlanCard(compact: compact)

            Image("mascot-unlocked")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 104 : 124, height: compact ? 104 : 124)
                .offset(y: compact ? -54 : -66)
                .shadow(color: PW.accent.opacity(0.20), radius: 18, y: 8)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 176 : 212)
    }

    private func miniPlanCard<Content: View>(
        angle: Double,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        compact: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: compact ? 122 : 138, height: compact ? 124 : 142)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PW.fg.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PW.fg.opacity(0.78), lineWidth: 1)
            )
            .shadow(color: PW.bg.opacity(0.18), radius: 14, y: 8)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }

    private func mainPlanCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMO PLAN")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(PW.accent)

                Spacer()

                Text(selectedPlan == .annual ? "7 DAYS FREE" : "WEEKLY")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(selectedPlan == .annual ? PW.mint : PW.amber)
                    .lineLimit(1)
            }

            planHeroRow(icon: "brain.head.profile", title: "Brain Training", value: "10 games", color: PW.mint, compact: compact)
            planHeroRow(icon: "shield.fill", title: "Focus Guard", value: "Whole feed", color: PW.accent, compact: compact)
            planHeroRow(icon: "bell.badge.fill", title: "Trial Reminder", value: selectedPlan == .annual ? "Before billing" : "Cancel anytime", color: PW.amber, compact: compact)
        }
        .padding(.horizontal, compact ? 13 : 15)
        .padding(.top, compact ? 38 : 44)
        .padding(.bottom, compact ? 12 : 14)
        .frame(width: compact ? 186 : 214, height: compact ? 154 : 178)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PW.fg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PW.accent.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: PW.bg.opacity(0.22), radius: 18, y: 12)
        .offset(y: compact ? 22 : 26)
        .accessibilityElement(children: .combine)
    }

    private func miniCardContent(
        title: String,
        value: String,
        icon: String,
        color: Color,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: compact ? 17 : 19, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.13)))

            Spacer(minLength: 2)

            Text(title)
                .font(.system(size: compact ? 9 : 10, weight: .black, design: .rounded))
                .foregroundStyle(PW.bg.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(value)
                .font(.system(size: compact ? 14 : 16, weight: .black, design: .rounded))
                .foregroundStyle(PW.bg)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(12)
    }

    private func planHeroRow(
        icon: String,
        title: String,
        value: String,
        color: Color,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 7 : 8) {
            Image(systemName: icon)
                .font(.system(size: compact ? 10 : 11, weight: .black))
                .foregroundStyle(color)
                .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
                .background(Circle().fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: compact ? 8 : 9, weight: .black, design: .rounded))
                    .foregroundStyle(PW.bg.opacity(0.44))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(value)
                    .font(.system(size: compact ? 11 : 12, weight: .black, design: .rounded))
                    .foregroundStyle(PW.bg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
    }

    private func planCards(compact: Bool) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 10
            let cardWidth = min((proxy.size.width - spacing) / 2, compact ? 168 : 184)

            HStack(spacing: spacing) {
                purchasePlanCard(
                    plan: .annual,
                    badge: "BEST VALUE",
                    title: "Yearly",
                    price: "$59.99/year",
                    detail: "$1.15/wk billed yearly",
                    compact: compact
                )
                .frame(width: cardWidth)

                purchasePlanCard(
                    plan: .weekly,
                    badge: nil,
                    title: "Weekly",
                    price: "$4.99/wk",
                    detail: "Billed weekly",
                    compact: compact
                )
                .frame(width: cardWidth)
            }
            .frame(width: (cardWidth * 2) + spacing)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: compact ? 104 : 116)
    }

    private func purchasePlanCard(
        plan: PaywallPlan,
        badge: String?,
        title: String,
        price: String,
        detail: String,
        compact: Bool
    ) -> some View {
        let selected = selectedPlan == plan
        let titleColor = selected ? PW.bg.opacity(0.62) : PW.fg2.opacity(0.86)
        let primaryColor = selected ? PW.bg : PW.fg
        let detailColor = selected ? PW.bg.opacity(0.54) : PW.fgMuted

        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(titleColor)

                    Spacer(minLength: 4)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PW.mint)
                    }
                }

                Text(price)
                    .font(.system(size: compact ? 19 : 21, weight: .black, design: .rounded))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(detail)
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 92 : 104, alignment: .leading)
            .padding(.horizontal, compact ? 13 : 14)
            .padding(.vertical, compact ? 13 : 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? PW.fg : PW.fg.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? PW.accent.opacity(0.68) : PW.fg.opacity(0.22), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(PW.bg)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(PW.amber))
                        .offset(x: 12, y: -12)
                }
            }
            .shadow(color: selected ? PW.bg.opacity(0.24) : PW.bg.opacity(0.12), radius: selected ? 16 : 8, y: selected ? 10 : 5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var ctaButton: some View {
        Button {
        } label: {
            HStack(spacing: 10) {
                Text(selectedPlan == .annual ? "Start for $0.00" : "Start Weekly Access")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .black))
            }
            .foregroundStyle(PW.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(PW.fg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PW.fg.opacity(0.70), lineWidth: 1)
            )
            .shadow(color: PW.bg.opacity(0.30), radius: 20, y: 12)
        }
        .buttonStyle(.plain)
    }

    private var trialNote: some View {
        Text(selectedPlan == .annual ? "No payment today. Reminder before trial ends." : "Cancel anytime in the App Store.")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(PW.fgMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("No ads. No data sold.")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PW.fgMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Circle()
                .fill(PW.fg.opacity(0.35))
                .frame(width: 3, height: 3)

            Text("Restore")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PW.fg2.opacity(0.86))
                .underline()
        }
    }
}

#Preview("Cute Paywall Design") {
    MemoCutePaywallPreviewView()
}
#endif
