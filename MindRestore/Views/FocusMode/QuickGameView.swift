import SwiftUI
import UIKit

struct TrainingGame: Identifiable {
    let type: ExerciseType
    let title: String
    let icon: String
    let color: Color

    var id: ExerciseType { type }
}

enum TrainingGameCatalog {
    static let memoryGames: [TrainingGame] = [
        TrainingGame(type: .visualMemory, title: "Visual Memory", icon: "square.grid.3x3.fill", color: AppColors.indigo),
        TrainingGame(type: .sequentialMemory, title: "Number Memory", icon: "number.circle.fill", color: AppColors.teal),
        TrainingGame(type: .chimpTest, title: "Chimp Test", icon: "pawprint.fill", color: AppColors.amber),
    ]

    static let speedGames: [TrainingGame] = [
        TrainingGame(type: .mathSpeed, title: "Math Sprint", icon: "multiply.circle.fill", color: AppColors.amber),
        TrainingGame(type: .colorMatch, title: "Color Match", icon: "paintpalette.fill", color: AppColors.violet),
        TrainingGame(type: .reactionTime, title: "Reaction Time", icon: "bolt.fill", color: AppColors.coral),
    ]

    static let focusUnlockGames: [TrainingGame] = memoryGames + speedGames
}

// MARK: - Spin results

enum SlotResult: Equatable {
    case game(UnlockGame)
    case freePass

    var analyticsName: String {
        switch self {
        case .game(let game): game.rawValue
        case .freePass: "freePass"
        }
    }
}

enum SlotSymbol: Hashable {
    case game(UnlockGame)
    case freePass(usedToday: Bool)
}

/// The live draw: FREE PASS at `UnlockRulebook.freePassWeight` while it is
/// still available today, otherwise one of the six games, uniformly.
enum SlotOdds {
    static func pick<R: RandomNumberGenerator>(freePassAvailable: Bool, using rng: inout R) -> SlotResult {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--unlock-game"), i + 1 < args.count {
            // A forced FREE PASS still honors once-a-day, so QA can check the second spin can't land it.
            if args[i + 1] == "freePass", freePassAvailable { return .freePass }
            if let game = UnlockGame(rawValue: args[i + 1]) { return .game(game) }
        }
        #endif
        if freePassAvailable, Double.random(in: 0..<1, using: &rng) < UnlockRulebook.freePassWeight { return .freePass }
        return .game(UnlockGame.allCases.randomElement(using: &rng)!)
    }
}

// MARK: - Memo's Booth — copy

enum FocusUnlockSlotCopy {
    static let eyebrow = "MEMO'S BOOTH"
    static let headline = "NO FEED TIL YOU TRAIN"
    static let pendingHeadline = "YOUR SPIN"
    static let idleStatus = "spin when you're ready"
    static let spinningStatus = "MEMO'S PICKING"
    static let freePassStatus = "FREE PASS · \(UnlockRulebook.freePassMinutes) MIN"

    static func landedStatus(for game: UnlockGame) -> String {
        "\(game.title.uppercased()) · \(game.passLineText.uppercased())"
    }
}

enum FocusUnlockSlotMode {
    case live
    /// Onboarding demo: rigged near-miss past a FREE PASS, no game launch,
    /// always the full ceremony.
    case demo
}

/// Guilt-friction confirm shown when a user tries to remove an app from
/// their block list. Emotional friction, not mechanical — catches the
/// impulse without a failure state or cooldown.
struct DeblockConfirmSheet: View {
    let onKeepGuard: () -> Void
    let onLowerAnyway: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            Image("mascot-locked-sad")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .shadow(color: OB.coral.opacity(0.22), radius: 20, y: 10)

            Text("You sure?\nThis hurts Memo.")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(OB.fg)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("You set this up to protect yourself. Lower your guard and the feed wins.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OB.fg2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 36)
                .padding(.top, 8)

            Spacer(minLength: 22)

            VStack(spacing: 12) {
                Button(action: onKeepGuard) {
                    Text("Keep my guard up")
                        .gradientButton()
                }

                Button(action: onLowerAnyway) {
                    Text("Let the feed win")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(OB.fg3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(OB.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - The machine (dealer + reel + spin) — shared by the fullscreen
// unlock view and the onboarding demo.

struct FocusUnlockSlotMachine: View {
    var mode: FocusUnlockSlotMode = .live
    /// Onboarding's hill: the dealer is a real cut-out (no blend over a dark
    /// backdrop) and SPIN is the chunky amber button.
    var onHill = false
    /// A spin taken in the last 30 minutes: show it centered, never re-roll.
    var pending: UnlockGame? = nil
    var reelHeight: CGFloat = 300
    var dealerSize: CGFloat = 150
    /// Fires the moment the reel lands (the onboarding demo listens here).
    var onLanded: ((SlotResult) -> Void)? = nil
    /// Live mode only: fires once, after PLAY or the FREE PASS hold.
    var onResult: ((SlotResult) -> Void)? = nil

    enum SlotPhase: Equatable {
        case idle
        case spinning
        case landed(SlotResult)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: SlotPhase = .idle
    @State private var strip: [SlotSymbol] = []
    @State private var reelOffset: CGFloat = 0
    @State private var spinIntensity: CGFloat = 0
    @State private var bulbPhase: CGFloat = 0
    @State private var bulbsDimmed = false
    @State private var dealerBounce = false
    @State private var countdown = 3
    @State private var isResumedSpin = false
    @State private var resultSent = false
    @State private var task: Task<Void, Never>?

    private let rowStride: CGFloat = 60
    private let windowHeight: CGFloat = 62
    /// Strip index centered before a spin; the spin strip keeps these rows so the reel doesn't jump.
    private let idleCenter = 3

    private var landed: SlotResult? {
        if case .landed(let result) = phase { return result }
        return nil
    }

    private var isFreePass: Bool { landed == .freePass }

    private var freePassUsedToday: Bool {
        mode == .live && !PendingSpinStore.shared.freePassAvailableToday
    }

    private var windowTint: Color {
        switch landed {
        case .game(let game): game.glyphTint
        case .freePass: OB.amber
        case nil: .white
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: FocusUnlockSlotCopy.idleStatus
        case .spinning: FocusUnlockSlotCopy.spinningStatus
        case .landed(.game(let game)): FocusUnlockSlotCopy.landedStatus(for: game)
        case .landed(.freePass): FocusUnlockSlotCopy.freePassStatus
        }
    }

    /// The demo hands off to the page's own CTA once it lands; FREE PASS hands off on its own.
    private var showsButton: Bool {
        switch phase {
        case .idle, .spinning: true
        case .landed(.game): mode == .live
        case .landed(.freePass): false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dealer
                .padding(.bottom, -dealerSize * 0.28)
                .scaleEffect(dealerBounce ? 1.12 : 1, anchor: .bottom)
                .accessibilityHidden(true)

            machineBody
                .zIndex(1)
                .overlay { OnboardingSparkBurst(active: isFreePass, radius: 140) }

            Group {
                if isFreePass {
                    FocusUnlockRewardTicket()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    FocusUnlockStatusPill(text: statusText, isLanded: landed != nil, landedColor: windowTint)
                }
            }
            .padding(.top, 14)

            if showsButton {
                spinButton
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: landed != nil)
        .onAppear(perform: setUp)
        .onDisappear { task?.cancel() }
        .accessibilityElement(children: .contain)
    }

    // MARK: Dealer

    @ViewBuilder private var dealer: some View {
        // The mp4 has a black background — .lighten keys it out over the dark
        // backdrop, and the machine's top edge hides the bottom strip.
        if onHill, Bundle.main.url(forResource: "mascot-dealer-alpha", withExtension: "mov") != nil {
            // HEVC with alpha, keyed from mascot-dealer.mp4, so the sky shows through cleanly.
            OnboardingLoopingVideo(videoName: "mascot-dealer-alpha", videoExt: "mov")
                .frame(width: dealerSize, height: dealerSize)
        } else if Bundle.main.url(forResource: "mascot-dealer", withExtension: "mp4") != nil {
            OnboardingLoopingVideo(videoName: "mascot-dealer", videoExt: "mp4")
                .blendMode(.lighten)
                .frame(width: dealerSize, height: dealerSize)
        } else {
            Image(isFreePass ? "mascot-celebrate" : "mascot-lookout")
                .resizable()
                .scaledToFit()
                .frame(height: dealerSize * 0.88)
        }
    }

    // MARK: Machine

    private var machineBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OB.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.black.opacity(0.55), lineWidth: 1.5)
                        .padding(3)
                )

            // Center window: a quiet highlight at rest, the game's color once it lands.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(windowTint.opacity(landed == nil ? 0.06 : 0.16))
                .frame(height: windowHeight)
                .padding(.horizontal, 12)

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { index, symbol in
                        let distance = rowDistance(for: index)
                        FocusUnlockReelRow(
                            symbol: symbol,
                            distance: distance,
                            showsPassLine: landed != nil && abs(distance) < 0.5,
                            isDimmed: landed != nil && abs(distance) >= 0.5
                        )
                        .frame(height: rowStride)
                        .padding(.horizontal, 16)
                    }
                }
                .frame(width: geometry.size.width, alignment: .top)
                .offset(y: reelOffset)
                .blur(radius: reduceMotion ? 0 : spinIntensity * 2.2)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.3),
                        .init(color: .white, location: 0.7),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(windowTint.opacity(landed == nil ? 0.22 : 0.9), lineWidth: landed == nil ? 1.5 : 2.5)
                .frame(height: windowHeight)
                .padding(.horizontal, 12)
                .shadow(color: windowTint.opacity(landed == nil ? 0 : 0.5), radius: 14)
                .allowsHitTesting(false)

            rimBulbs
        }
        .frame(height: reelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: (landed == nil ? OB.accent : windowTint).opacity(landed == nil ? 0.18 : 0.45),
                radius: landed == nil ? 24 : 36, y: 8)
        .animation(.easeOut(duration: 0.3), value: phase)
        .accessibilityLabel("Brain game picker")
        .accessibilityValue(accessibilityValue)
    }

    /// Marquee bulbs around the rim: they chase while spinning, blink on the
    /// landing, and go solid gold for a FREE PASS.
    private var rimBulbs: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Group {
            if isFreePass {
                shape.stroke(
                    LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), OB.amber], startPoint: .top, endPoint: .bottom),
                    lineWidth: 3
                )
            } else {
                shape.stroke(OB.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 12], dashPhase: bulbPhase))
            }
        }
        .padding(5)
        .opacity(bulbsDimmed ? 0.3 : 1)
        .shadow(color: OB.amber.opacity(0.6), radius: 4)
        .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        switch phase {
        case .idle: "Ready to spin"
        case .spinning: "Spinning"
        case .landed(.game(let game)): game.title
        case .landed(.freePass): "Free pass"
        }
    }

    // MARK: Button

    @ViewBuilder
    private var spinButton: some View {
        if onHill {
            ChunkyButton(title: buttonTitle, systemImage: nil, style: .amber, action: buttonTapped)
                .disabled(phase == .spinning)
                .opacity(phase == .spinning ? 0.6 : 1)
                .accessibilityLabel(landed == nil ? "Spin" : "Play")
        } else {
            classicSpinButton
        }
    }

    private var classicSpinButton: some View {
        Button(action: buttonTapped) {
            Text(buttonTitle)
                .tracking(1.2)
                .contentTransition(.numericText())
                .gradientButton()
        }
        .disabled(phase == .spinning)
        .opacity(phase == .spinning ? 0.55 : 1)
        .buttonStyle(.plain)
        .accessibilityLabel(landed == nil ? "Spin" : "Play")
        .accessibilityHint(landed == nil ? "Memo picks the game that unlocks your apps" : "Starts the game now")
    }

    private var buttonTitle: String {
        switch phase {
        case .idle: "SPIN"
        case .spinning: "SPINNING"
        case .landed: isResumedSpin ? "PLAY" : "PLAY · \(countdown)"
        }
    }

    private func buttonTapped() {
        switch phase {
        case .idle: spin()
        case .landed(let result): deliver(result)
        case .spinning: break
        }
    }

    // MARK: Reel geometry

    private func offset(centering index: Int) -> CGFloat {
        reelHeight / 2 - (CGFloat(index) + 0.5) * rowStride
    }

    private func rowDistance(for index: Int) -> CGFloat {
        (reelOffset + (CGFloat(index) + 0.5) * rowStride - reelHeight / 2) / rowStride
    }

    private func symbol(for result: SlotResult) -> SlotSymbol {
        switch result {
        case .game(let game): .game(game)
        case .freePass: .freePass(usedToday: false)
        }
    }

    /// Each game and FREE PASS equally dense on the strip.
    private func randomSymbol() -> SlotSymbol {
        let pick = Int.random(in: 0...UnlockGame.allCases.count)
        return pick == UnlockGame.allCases.count ? .freePass(usedToday: freePassUsedToday) : .game(UnlockGame.allCases[pick])
    }

    private func setUp() {
        guard strip.isEmpty else { return }
        let center = pending.map(SlotSymbol.game) ?? .game(.visualMemory)
        let others = UnlockGame.allCases.filter { SlotSymbol.game($0) != center }.map(SlotSymbol.game)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            strip = [others[0], others[1], .freePass(usedToday: freePassUsedToday), center, others[2], others[3], others[4]]
            reelOffset = offset(centering: idleCenter)
            if mode == .live, let pending {
                isResumedSpin = true
                phase = .landed(.game(pending))
            }
        }
        if mode == .live, let pending {
            Analytics.unlockPendingSpinResumed(game: pending.rawValue)
        }
    }

    // MARK: Spin

    private func spin() {
        guard phase == .idle else { return }

        let result: SlotResult
        if mode == .demo {
            result = .game(.visualMemory)
        } else {
            var rng = SystemRandomNumberGenerator()
            result = SlotOdds.pick(freePassAvailable: PendingSpinStore.shared.freePassAvailableToday, using: &rng)
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        phase = .spinning

        var symbols = Array(strip.prefix(idleCenter + 1)) + (0..<22).map { _ in randomSymbol() }
        let landIndex = symbols.count
        if mode == .demo {
            // Near-miss: a FREE PASS crawls through the window right before Visual Memory settles.
            symbols[landIndex - 1] = .freePass(usedToday: false)
        }
        symbols.append(symbol(for: result))
        symbols += (0..<3).map { _ in randomSymbol() }
        strip = symbols

        let finalOffset = offset(centering: landIndex)

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.5)) { reelOffset = finalOffset }
            task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                land(result)
            }
            return
        }

        // Ceremony decays: the first spin of the day gets the full ritual.
        // Demo spins always run the full ceremony — it's the sales pitch.
        let fullCeremony = mode == .demo || isFirstSpinToday
        if mode == .live && fullCeremony { markFullSpinToday() }
        let duration = fullCeremony ? 2.3 : 1.4

        task = Task { @MainActor in
            await animateSpin(to: finalOffset, duration: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.56)) {
                reelOffset = finalOffset
                spinIntensity = 0
            }
            land(result)
        }
    }

    /// Frame-driven reel: ease-out-quart travel to an overshoot point, ticking
    /// on real row crossings so the cadence is the physics.
    private func animateSpin(to finalOffset: CGFloat, duration: Double) async {
        let startOffset = reelOffset
        let distance = (finalOffset - 14) - startOffset
        let startedAt = Date()
        var lastCentered = Int.min
        var lastTickAt = Date.distantPast

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startedAt)
            let t = min(elapsed / duration, 1)
            reelOffset = startOffset + distance * CGFloat(1 - pow(1 - t, 4))
            spinIntensity = CGFloat(pow(1 - t, 2))
            bulbPhase = CGFloat(-elapsed * 60)

            let centered = Int(((reelHeight / 2 - reelOffset) / rowStride - 0.5).rounded())
            if centered != lastCentered {
                lastCentered = centered
                if Date().timeIntervalSince(lastTickAt) >= 0.045 {
                    lastTickAt = Date()
                    HapticService.tap()
                    SlotSound.tick()
                }
            }

            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    private func land(_ result: SlotResult) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            phase = .landed(result)
        }
        onLanded?(result)

        if mode == .live {
            let attempt = max(1, UserDefaults(suiteName: "group.com.memori.shared")?.integer(forKey: "focus_daily_attempt_count") ?? 0)
            Analytics.unlockSpin(result: result.analyticsName, attempt: attempt)
        }

        switch result {
        case .game:
            SlotSound.lock()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            task = Task { @MainActor in
                await blinkBulbs()
                guard mode == .live else { return }
                for remaining in [2, 1] {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation { countdown = remaining }
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                deliver(result)
            }
        case .freePass:
            SlotSound.chime()
            HapticService.complete()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { dealerBounce = true }
            task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.22))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dealerBounce = false }
                try? await Task.sleep(for: .seconds(1.18))
                guard !Task.isCancelled, mode == .live else { return }
                deliver(result)
            }
        }
    }

    private func blinkBulbs() async {
        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.1)) { bulbsDimmed = true }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeInOut(duration: 0.1)) { bulbsDimmed = false }
            try? await Task.sleep(for: .seconds(0.12))
        }
    }

    private func deliver(_ result: SlotResult) {
        guard mode == .live, !resultSent else { return }
        resultSent = true
        task?.cancel()
        onResult?(result)
    }

    // MARK: Ceremony decay

    private static let fullSpinDayKey = "focus_slot_last_full_spin_day"

    private var isFirstSpinToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.fullSpinDayKey) as? Date else {
            return true
        }
        return !Calendar.current.isDate(last, inSameDayAs: .now)
    }

    private func markFullSpinToday() {
        UserDefaults.standard.set(Date(), forKey: Self.fullSpinDayKey)
    }
}

// MARK: - Atmosphere — a dark room with one warm spotlight on the machine.

struct FocusSlotAtmosphere: View {
    var body: some View {
        ZStack {
            OB.bg
            // Spotlight cone from above, pooling on the machine.
            RadialGradient(
                colors: [Color(red: 1, green: 0.76, blue: 0.28).opacity(0.13), .clear],
                center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 360
            )
            LinearGradient(
                colors: [Color(red: 1, green: 0.8, blue: 0.4).opacity(0.05), .clear],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)
            )
            // Vignette so the edges of the room fall away.
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 220, endRadius: 620)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Fullscreen unlock view

struct FocusUnlockSlotView: View {
    let pending: UnlockGame?
    let onResult: (SlotResult) -> Void

    init(pending: UnlockGame?, onResult: @escaping (SlotResult) -> Void) {
        self.pending = pending
        self.onResult = onResult
    }

    private var attempt: Int {
        max(1, UserDefaults(suiteName: "group.com.memori.shared")?.integer(forKey: "focus_daily_attempt_count") ?? 0)
    }

    var body: some View {
        GeometryReader { geometry in
            // SE-class screens get a smaller sign and dealer so the 5-row machine still fits.
            let compact = geometry.size.height < 700
            VStack(spacing: 0) {
                VStack(spacing: compact ? 8 : 12) {
                    BoothMarqueeSign(scale: compact ? 0.78 : 1)

                    Text(pending == nil ? FocusUnlockSlotCopy.headline : FocusUnlockSlotCopy.pendingHeadline)
                        .font(.system(size: compact ? 28 : 32, weight: .black, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 6) {
                        BlockedAppIcon(size: 20)
                        Text("attempt #\(attempt) today")
                    }
                    .font(.brand(size: 12, weight: .heavy))
                    .foregroundStyle(OB.fg2)
                }
                .padding(.top, compact ? 8 : 20)

                Spacer(minLength: 8)

                FocusUnlockSlotMachine(
                    mode: .live,
                    pending: pending,
                    reelHeight: 300,
                    dealerSize: compact ? 118 : 150,
                    onResult: onResult
                )
                .frame(maxWidth: 360)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background { FocusSlotAtmosphere() }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
    }
}

/// MEMO'S BOOTH as a real lit sign: chunky two-line letters on a dark board,
/// framed by chasing bulbs.
private struct BoothMarqueeSign: View {
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chase: CGFloat = 0

    private var letterFill: LinearGradient {
        LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.82), OB.amber], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let board = RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
        VStack(spacing: -4 * scale) {
            Text("MEMO'S")
            Text("BOOTH")
        }
        .font(.system(size: 30 * scale, weight: .black, design: .rounded))
        .tracking(4 * scale)
        .foregroundStyle(letterFill)
        .shadow(color: OB.amber.opacity(0.7), radius: 10 * scale)
        .padding(.horizontal, 30 * scale)
        .padding(.vertical, 14 * scale)
        .background(
            board.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.1), Color(red: 0.08, green: 0.04, blue: 0.07)],
                                      startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            board.stroke(Color(red: 1, green: 0.85, blue: 0.5),
                         style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, dash: [0.1, 11 * scale], dashPhase: chase))
                .padding(5 * scale)
                .shadow(color: OB.amber.opacity(0.9), radius: 4 * scale)
        )
        .overlay(board.strokeBorder(OB.amber.opacity(0.35), lineWidth: 1.5))
        .shadow(color: OB.amber.opacity(0.25), radius: 24 * scale)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { chase = -22 * scale }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FocusUnlockSlotCopy.eyebrow)
    }
}

/// Pops out of the machine when the reel lands on FREE PASS.
private struct FocusUnlockRewardTicket: View {
    var body: some View {
        VStack(spacing: 2) {
            SignageText(text: "FREE PASS", colors: [Color(red: 1, green: 0.9, blue: 0.6), OB.amber], size: 40)
            Text("\(UnlockRulebook.freePassMinutes) MINUTES BACK")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(OB.fg2)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(OB.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OB.amber.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
        )
        .shadow(color: OB.amber.opacity(0.25), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Free pass. \(UnlockRulebook.freePassMinutes) minutes back")
    }
}

// MARK: - Reel row

private struct FocusUnlockStatusPill: View {
    let text: String
    let isLanded: Bool
    let landedColor: Color

    var body: some View {
        styledText
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .animation(.easeInOut(duration: 0.22), value: text)
    }

    private var styledText: some View {
        Text(text.uppercased())
            .font(.system(size: isLanded ? 13 : 11, weight: .heavy, design: .monospaced))
            .tracking(isLanded ? 0.4 : 1.0)
            .foregroundStyle(isLanded ? landedColor : OB.fg3)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(.opacity)
    }
}

private struct FocusUnlockReelRow: View {
    let symbol: SlotSymbol
    let distance: CGFloat
    let showsPassLine: Bool
    let isDimmed: Bool

    private var nearness: CGFloat { max(0, 1 - abs(distance)) }

    var body: some View {
        content
            // Rows swell toward the window: 52 pt at the edges, 62 pt centered.
            .frame(height: 52 + 10 * nearness * nearness)
            .opacity(isDimmed ? 0.3 : max(0.45, 1 - Double(abs(distance)) * 0.25))
            .saturation(isDimmed ? 0.5 : 1)
    }

    @ViewBuilder private var content: some View {
        switch symbol {
        case .game(let game):
            HStack(spacing: 12) {
                GameGlyph(game: game, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.brand(size: 15, weight: .black))
                        .foregroundStyle(OB.fg)
                        .lineLimit(1)
                    if showsPassLine {
                        Text(game.passLineText)
                            .font(.brand(size: 10, weight: .heavy))
                            .foregroundStyle(OB.fg2)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        case .freePass(let usedToday):
            HStack(spacing: 12) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: 40, height: 40)
                Text("FREE PASS")
                    .font(.system(size: 16, weight: .black).italic())
                    .foregroundStyle(.black)
                Spacer(minLength: 0)
                if usedToday {
                    Text("USED TODAY")
                        .font(.brand(size: 10, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), OB.amber], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(usedToday ? 0.45 : 1)
        }
    }
}

#Preview("Focus Unlock Slot") {
    FocusUnlockSlotView(pending: nil) { _ in }
}
