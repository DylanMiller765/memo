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
        TrainingGame(type: .sequentialMemory, title: "Number Memory", icon: "number.circle.fill", color: AppColors.teal),
        TrainingGame(type: .visualMemory, title: "Visual Memory", icon: "square.grid.3x3.fill", color: AppColors.indigo),
        TrainingGame(type: .chunkingTraining, title: "Chunking", icon: "rectangle.split.3x1.fill", color: AppColors.rose),
        TrainingGame(type: .verbalMemory, title: "Verbal Memory", icon: "text.book.closed.fill", color: AppColors.violet),
    ]

    static let speedGames: [TrainingGame] = [
        TrainingGame(type: .reactionTime, title: "Reaction Time", icon: "bolt.fill", color: AppColors.coral),
        TrainingGame(type: .mathSpeed, title: "Math Speed", icon: "multiply.circle.fill", color: AppColors.amber),
        TrainingGame(type: .speedMatch, title: "Speed Match", icon: "bolt.square.fill", color: AppColors.sky),
        TrainingGame(type: .colorMatch, title: "Color Match", icon: "paintpalette.fill", color: AppColors.violet),
    ]

    static let focusGames: [TrainingGame] = [
        TrainingGame(type: .dualNBack, title: "Dual N-Back", icon: "square.grid.3x3", color: AppColors.sky),
        TrainingGame(type: .chimpTest, title: "Chimp Test", icon: "pawprint.fill", color: AppColors.amber),
    ]

    static let focusUnlockGames: [TrainingGame] = memoryGames + speedGames + focusGames
}

/// The spin decides the game AND the unlock window — coupled payouts.
/// Harder games pay disproportionately more, so the rare tile is a real
/// jackpot, but the payout only cashes when the game is completed.
enum FocusUnlockPayout {
    enum Tier: CaseIterable {
        case quick   // easy reps, short window
        case solid   // memory games, medium window
        case jackpot // hardest games, big window

        var minutes: Int {
            switch self {
            case .quick: return 5
            case .solid: return 10
            case .jackpot: return 20
            }
        }

        /// Spin weights: commons dominate so the jackpot stays an event.
        var weight: Double {
            switch self {
            case .quick: return 0.60
            case .solid: return 0.30
            case .jackpot: return 0.10
            }
        }
    }

    static func tier(for type: ExerciseType) -> Tier {
        switch type {
        case .dualNBack, .chimpTest:
            return .jackpot
        case .sequentialMemory, .visualMemory, .chunkingTraining, .verbalMemory:
            return .solid
        default:
            return .quick
        }
    }

    static func minutes(for type: ExerciseType) -> Int {
        tier(for: type).minutes
    }

    /// Pick a tier by weight, then a uniform game within that tier. Falls
    /// back across tiers if the pool doesn't cover one.
    static func weightedRandomGame(
        from games: [TrainingGame],
        roll: Double = .random(in: 0..<1)
    ) -> TrainingGame? {
        guard !games.isEmpty else { return nil }

        var cumulative = 0.0
        var chosenTier: Tier = .quick
        for tier in Tier.allCases {
            cumulative += tier.weight
            if roll < cumulative {
                chosenTier = tier
                break
            }
        }

        let pool = games.filter { tier(for: $0.type) == chosenTier }
        return pool.randomElement() ?? games.randomElement()
    }
}

enum FocusUnlockCompletionGate {
    static func shouldGrant(completedGameRawValue: String?, expectedGame: ExerciseType?) -> Bool {
        guard
            let expectedGame,
            let completedGameRawValue,
            let completedGame = ExerciseType(rawValue: completedGameRawValue)
        else {
            return false
        }

        return completedGame == expectedGame
    }
}


// MARK: - Memo's Booth — copy

enum FocusUnlockSlotCopy {
    static let eyebrow = "MEMO'S BOOTH"
    static let headline = "NO FEED TIL YOU TRAIN"
    static let subhead = "Play a brain game. Get your time back."
    static let idleStatus = "spin when you're ready"
    static let spinningStatus = "MEMO'S PICKING"

    /// Rotating landed lines per payout tier — fresh screenshots every spin.
    static func landedStatus(for game: TrainingGame?) -> String {
        guard let game else { return "LOCKED IN" }
        let pool: [String]
        switch FocusUnlockPayout.tier(for: game.type) {
        case .quick:
            pool = ["QUICK REP, QUICK FIX.", "EASY ONE. IN AND OUT.", "WARM-UP PACE. GO."]
        case .solid:
            pool = ["TEN ON THE LINE.", "MEMORY PAYS DOUBLE.", "SOLID PULL. EARN IT."]
        case .jackpot:
            pool = ["20 MIN IF YOU SURVIVE.", "JACKPOT. NOW PROVE IT.", "THE BIG ONE. DON'T CHOKE."]
        }
        return "\(game.title.uppercased()). \(pool.randomElement() ?? "GO.")"
    }
}

enum FocusUnlockSlotMode {
    case live
    /// Onboarding demo: rigged near-miss past a jackpot tile, no game launch,
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

// MARK: - The machine (mascot + reel + spin) — shared by the fullscreen
// unlock view and the onboarding demo.

struct FocusUnlockSlotMachine: View {
    let games: [TrainingGame]
    var mode: FocusUnlockSlotMode = .live
    /// Fires the moment the reel lands: (game, payout minutes).
    var onLanded: ((TrainingGame, Int) -> Void)? = nil
    /// Live mode only: fires after the landed hold to launch the game.
    var onGameSelected: ((TrainingGame) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: SlotPhase = .idle
    @State private var reelItems: [TrainingGame] = []
    @State private var reelOffset: CGFloat = 0
    @State private var selectedGame: TrainingGame?
    @State private var spinIntensity: CGFloat = 0
    @State private var launchTask: Task<Void, Never>?

    private let reelHeight: CGFloat = 300
    private let tileHeight: CGFloat = 96
    private let tileSpacing: CGFloat = 4

    private enum SlotPhase {
        case idle
        case spinning
        case landed
    }

    private var rowStride: CGFloat { tileHeight + tileSpacing }
    private var centerOffset: CGFloat { (reelHeight - tileHeight) / 2 }
    private var canSpin: Bool { phase == .idle && !games.isEmpty }

    private var statusText: String {
        switch phase {
        case .idle: FocusUnlockSlotCopy.idleStatus
        case .spinning: FocusUnlockSlotCopy.spinningStatus
        case .landed: FocusUnlockSlotCopy.landedStatus(for: selectedGame)
        }
    }

    private var landedTier: FocusUnlockPayout.Tier? {
        guard phase == .landed, let selectedGame else { return nil }
        return FocusUnlockPayout.tier(for: selectedGame.type)
    }

    private var windowTint: Color {
        switch landedTier {
        case .jackpot: return OB.amber
        case .solid: return OB.accent
        case .quick: return OB.success
        case nil: return phase == .spinning ? OB.accent.opacity(0.7) : Color.white.opacity(0.22)
        }
    }

    private var mascotPose: String {
        switch phase {
        case .idle, .spinning:
            return "mascot-lookout"
        case .landed:
            return landedTier == .jackpot ? "mascot-celebrate" : "mascot-cool"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Memo the dealer, leaning on the machine's top edge. The animated
            // dealer loop is the identity when bundled; static poses fall back.
            // The mp4 has a black background — .lighten keys it out over the
            // dark backdrop, and the machine's top edge hides the bottom strip.
            Group {
                if Bundle.main.url(forResource: "mascot-dealer", withExtension: "mp4") != nil {
                    OnboardingLoopingVideo(videoName: "mascot-dealer", videoExt: "mp4")
                        .blendMode(.lighten)
                        .frame(width: 150, height: 150)
                } else {
                    ZStack {
                        ForEach(["mascot-lookout", "mascot-cool", "mascot-celebrate"], id: \.self) { pose in
                            Image(pose)
                                .resizable()
                                .scaledToFit()
                                .opacity(pose == mascotPose ? 1 : 0)
                        }
                    }
                    .frame(height: 132)
                    .animation(.easeInOut(duration: 0.25), value: mascotPose)
                }
            }
            .padding(.bottom, -42)
            .accessibilityHidden(true)

            machineBody
                .zIndex(1)

            if let selectedGame, phase == .landed {
                FocusUnlockRewardTicket(
                    minutes: FocusUnlockPayout.minutes(for: selectedGame.type),
                    color: windowTint,
                    isPreview: mode == .demo
                )
                .padding(.top, 14)
                .transition(.scale.combined(with: .opacity))
            } else {
                statusLine
                    .padding(.top, 14)
            }

            // In the onboarding demo the page's own CTA takes over once the
            // reel lands — a dimmed dead SPIN next to it would just confuse.
            if phase != .landed {
                spinButton
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: phase == .landed)
        .onAppear {
            if reelItems.isEmpty {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    setIdleReel()
                }
            }
        }
        .onDisappear {
            launchTask?.cancel()
        }
        .accessibilityElement(children: .contain)
    }

    private var machineBody: some View {
        ZStack {
            // Machined frame: outer hairline + inset bezel so the reel reads
            // as recessed hardware, not a painted panel.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OB.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.black.opacity(0.55), lineWidth: 1.5)
                        .padding(3)
                )

            GeometryReader { geometry in
                VStack(spacing: tileSpacing) {
                    ForEach(Array(reelItems.enumerated()), id: \.offset) { index, game in
                        FocusUnlockReelTile(
                            game: game,
                            isSelected: selectedGame?.type == game.type && phase == .landed,
                            isLanded: phase == .landed,
                            distanceFromCenter: rowDistance(for: index),
                            spinIntensity: spinIntensity
                        )
                        .frame(height: tileHeight)
                        .padding(.horizontal, 10)
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
                        .init(color: .black, location: 0.13),
                        .init(color: .black, location: 0.87),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Recessed depth: the reel falls away into shadow at both ends.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
            }
            .allowsHitTesting(false)

            // Selection window — clean tinted stroke + glow, no clipped chrome.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(windowTint, lineWidth: 2.5)
                .frame(height: tileHeight + 10)
                .padding(.horizontal, 6)
                .shadow(color: windowTint.opacity(phase == .landed ? 0.55 : 0.12), radius: 16)
                .animation(.easeOut(duration: 0.25), value: phase)
                .allowsHitTesting(false)
        }
        .frame(height: reelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // Machine glow breathes accent at rest, flashes the payout color on
        // landing — the whole cabinet celebrates, not just the window.
        .shadow(color: windowTint.opacity(phase == .landed ? 0.45 : 0.18), radius: phase == .landed ? 36 : 24, y: 8)
        .animation(.easeOut(duration: 0.3), value: phase)
        .accessibilityLabel("Brain game picker")
        .accessibilityValue(selectedGame?.title ?? "Ready to spin")
    }

    private var statusLine: some View {
        let isLanded = phase == .landed
        return FocusUnlockStatusPill(
            text: statusText,
            isLanded: isLanded,
            landedColor: windowTint
        )
    }

    private var spinButton: some View {
        Button {
            spin()
        } label: {
            Text(phase == .spinning ? "SPINNING" : "SPIN")
                .tracking(1.2)
                .gradientButton()
        }
        .disabled(!canSpin)
        .opacity(canSpin ? 1 : 0.55)
        .buttonStyle(.plain)
        .accessibilityLabel("Spin")
        .accessibilityHint("Chooses a random brain game and unlock window")
    }

    private func rowDistance(for index: Int) -> CGFloat {
        let tileCenter = reelOffset + CGFloat(index) * rowStride + tileHeight / 2
        return (tileCenter - reelHeight / 2) / rowStride
    }

    private func setIdleReel() {
        reelItems = Array(repeating: games, count: 3).flatMap { $0 }
        let middleIndex = max(games.count, 0)
        reelOffset = centerOffset - CGFloat(middleIndex) * rowStride
    }

    // MARK: Spin

    private func spin() {
        guard canSpin else { return }

        let winner: TrainingGame
        if mode == .demo {
            // Rigged: land Visual Memory — the strongest game to hand the
            // user right after — following a near-miss past the jackpot.
            winner = games.first { $0.type == .visualMemory } ?? games[0]
        } else {
            guard let chosen = FocusUnlockPayout.weightedRandomGame(from: games) else { return }
            winner = chosen
        }

        if mode == .live {
            Analytics.focusUnlockSpinStarted()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        selectedGame = nil
        phase = .spinning

        if reduceMotion {
            reelItems = games
            if let winnerIndex = games.firstIndex(where: { $0.type == winner.type }) {
                withAnimation(.easeOut(duration: 0.5)) {
                    reelOffset = centerOffset - CGFloat(winnerIndex) * rowStride
                }
            }
            launchTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                finishLanding(winner)
            }
            return
        }

        // Ceremony decays: first spin of the day gets the full ritual.
        // Demo spins always run the full ceremony — it's the sales pitch.
        let fullCeremony = mode == .demo || isFirstSpinToday
        if mode == .live && fullCeremony { markFullSpinToday() }
        let duration = fullCeremony ? 2.3 : 1.1
        let loops = fullCeremony ? 4 : 2

        var spinItems = Array(repeating: games, count: loops).flatMap { $0 }
        if mode == .demo {
            // Near-miss: the jackpot tile crawls through the window right
            // before the winner settles.
            if let jackpotGame = games.first(where: { FocusUnlockPayout.tier(for: $0.type) == .jackpot }) {
                spinItems.append(jackpotGame)
            }
        } else {
            let winnerIndex = games.firstIndex(where: { $0.type == winner.type }) ?? 0
            spinItems += Array(games.prefix(winnerIndex))
        }
        spinItems.append(winner)
        let landIndex = spinItems.count - 1

        // Rows below the winner so the window never sits at the end of the
        // world — an empty row under the landed tile reads as a bug.
        spinItems += games.filter { $0.type != winner.type }.prefix(2)

        reelItems = spinItems
        reelOffset = centerOffset
        spinIntensity = 0

        let finalOffset = centerOffset - CGFloat(landIndex) * rowStride

        launchTask = Task { @MainActor in
            await animateSpin(to: finalOffset, duration: duration)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.26, dampingFraction: 0.56)) {
                reelOffset = finalOffset
                spinIntensity = 0
            }
            playLockClunk()

            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            finishLanding(winner)
        }
    }

    /// Frame-driven reel: ease-out-quart travel to an overshoot point, with
    /// haptic + sound ticks fired on actual tile crossings so the cadence is
    /// the physics (fast roll → sparse, punchy clicks at the end).
    private func animateSpin(to finalOffset: CGFloat, duration: Double) async {
        let startOffset = reelOffset
        let overshootTarget = finalOffset - 14
        let distance = overshootTarget - startOffset
        let startedAt = Date()

        let tick = UIImpactFeedbackGenerator(style: .rigid)
        tick.prepare()
        var lastCenteredIndex = Int.min
        var lastTickAt = Date.distantPast

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startedAt)
            let t = min(elapsed / duration, 1)
            let eased = 1 - pow(1 - t, 4)
            reelOffset = startOffset + distance * CGFloat(eased)
            spinIntensity = CGFloat(pow(1 - t, 2))

            let centered = Int(((centerOffset - reelOffset) / rowStride).rounded())
            if centered != lastCenteredIndex {
                lastCenteredIndex = centered
                // Gate to ~14 ticks/sec max so the early blur doesn't saturate
                // the Taptic Engine; late crossings all land individually.
                if Date().timeIntervalSince(lastTickAt) > 0.07 {
                    lastTickAt = Date()
                    tick.impactOccurred(intensity: 0.55 + 0.45 * t)
                    tick.prepare()
                    SoundService.shared.playReelTick()
                }
            }

            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    private func playLockClunk() {
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        rigid.prepare()
        heavy.prepare()
        rigid.impactOccurred()
        SoundService.shared.playReelLock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            heavy.impactOccurred()
        }
    }

    private func finishLanding(_ winner: TrainingGame) {
        selectedGame = winner
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            phase = .landed
        }

        let minutes = FocusUnlockPayout.minutes(for: winner.type)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if FocusUnlockPayout.tier(for: winner.type) == .jackpot {
            SoundService.shared.playJackpotSting()
        }

        if mode == .live {
            Analytics.focusUnlockSpinLanded(gameType: winner.type.rawValue, payoutMinutes: minutes)
        }
        onLanded?(winner, minutes)

        guard mode == .live, let onGameSelected else { return }
        launchTask = Task { @MainActor in
            // Hold long enough to read the landed line before the handoff.
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            onGameSelected(winner)
        }
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

// MARK: - Atmosphere — a quiet midnight arcade wall behind Memo's Booth.

struct FocusSlotAtmosphere: View {
    var body: some View {
        ZStack {
            OB.bg

            FocusSlotBackdropTexture()

            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(OB.accent.opacity(0.035))
                .frame(width: 430, height: 560)
                .blur(radius: 34)
                .offset(y: 170)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct FocusSlotBackdropTexture: View {
    private let flecks: [(x: CGFloat, y: CGFloat, size: CGFloat, color: Color)] = [
        (0.08, 0.18, 4, OB.accent.opacity(0.55)),
        (0.14, 0.43, 2, OB.memoPurple.opacity(0.42)),
        (0.88, 0.24, 5, OB.accent.opacity(0.46)),
        (0.82, 0.55, 2, OB.memoPurple.opacity(0.36)),
        (0.11, 0.74, 3, OB.accent.opacity(0.34)),
        (0.91, 0.82, 4, OB.memoPurple.opacity(0.30)),
        (0.73, 0.12, 2, OB.accent.opacity(0.28)),
        (0.29, 0.89, 2, OB.memoPurple.opacity(0.24))
    ]

    var body: some View {
        Canvas { context, size in
            for fleck in flecks {
                let point = CGPoint(x: size.width * fleck.x, y: size.height * fleck.y)
                let rect = CGRect(
                    x: point.x - fleck.size / 2,
                    y: point.y - fleck.size / 2,
                    width: fleck.size,
                    height: fleck.size
                )
                context.fill(Path(ellipseIn: rect), with: .color(fleck.color))
            }
        }
    }
}

// MARK: - Fullscreen unlock view

struct FocusUnlockSlotView: View {
    let games: [TrainingGame]
    let onGameSelected: (TrainingGame) -> Void

    var body: some View {
        ZStack {
            FocusSlotAtmosphere()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                VStack(spacing: 8) {
                    FocusSlotMarquee(title: FocusUnlockSlotCopy.eyebrow)

                    Text(FocusUnlockSlotCopy.headline)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(OB.fg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .accessibilityAddTraits(.isHeader)

                    Text(FocusUnlockSlotCopy.subhead)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(OB.fg2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 16)

                FocusUnlockSlotMachine(
                    games: games,
                    mode: .live,
                    onGameSelected: onGameSelected
                )
                .frame(maxWidth: 360)

                Spacer(minLength: 28)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
    }
}

private struct FocusSlotMarquee: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(OB.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(OB.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(OB.accent.opacity(0.30), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Circle()
                    .fill(OB.amber.opacity(0.82))
                    .frame(width: 4, height: 4)
                    .padding(.leading, 6)
            }
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(OB.amber.opacity(0.82))
                    .frame(width: 4, height: 4)
                    .padding(.trailing, 6)
            }
    }
}

private struct FocusUnlockRewardTicket: View {
    let minutes: Int
    let color: Color
    let isPreview: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(isPreview ? "IF YOU FINISH" : "TIME BACK")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(OB.fg2)
                Text("\(minutes) MINUTES")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(OB.fg)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
        )
        .shadow(color: color.opacity(0.20), radius: 12, y: 5)
        .accessibilityLabel(isPreview
            ? "\(minutes) minutes if you complete the game"
            : "\(minutes) minutes back")
    }
}

// MARK: - Reel tile

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

private struct FocusUnlockReelTile: View {
    let game: TrainingGame
    let isSelected: Bool
    let isLanded: Bool
    let distanceFromCenter: CGFloat
    let spinIntensity: CGFloat

    private var tier: FocusUnlockPayout.Tier {
        FocusUnlockPayout.tier(for: game.type)
    }

    private var payoutColor: Color {
        switch tier {
        case .quick: return OB.fg2
        case .solid: return OB.accent
        case .jackpot: return OB.amber
        }
    }

    private var normalizedDistance: CGFloat {
        min(abs(distanceFromCenter), 2.4)
    }

    private var depthScale: CGFloat {
        max(0.82, 1 - normalizedDistance * 0.09)
    }

    private var depthOpacity: Double {
        if isLanded && !isSelected {
            // The winner owns the landed frame — everything else recedes hard.
            return max(0.12, 0.30 - Double(normalizedDistance) * 0.12)
        }
        return max(0.40, 1 - Double(normalizedDistance) * 0.26)
    }

    private var depthRotation: Double {
        Double(distanceFromCenter) * -12
    }

    private var cylinderYOffset: CGFloat {
        let clamped = max(-2.2, min(2.2, distanceFromCenter))
        return CGFloat(sin(Double(clamped) * 0.62)) * 4
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(game.color.opacity(isSelected ? 0.45 : 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(game.color.opacity(0.65), lineWidth: 1)
                    )
                Image(systemName: game.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? .white : game.color)
            }
            .frame(width: 46, height: 46)
            .shadow(color: game.color.opacity(isSelected ? 0.65 : 0.30), radius: 9, y: 2)

            Text(game.title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(OB.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(FocusUnlockPayout.minutes(for: game.type)) MIN")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? OB.bg : payoutColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(payoutColor.opacity(isSelected ? 1.0 : 0.16), in: Capsule())
                    .overlay(Capsule().stroke(payoutColor.opacity(isSelected ? 0 : 0.55), lineWidth: 1))
                    .scaleEffect(isSelected ? 1.1 : 1)

                if tier == .jackpot {
                    Text("◆ RARE")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(OB.amber.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [game.color.opacity(0.36), game.color.opacity(0.12)]
                            : [game.color.opacity(0.14), game.color.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? game.color.opacity(0.8) : game.color.opacity(0.26), lineWidth: isSelected ? 1.4 : 1)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(game.color.opacity(isSelected ? 1.0 : 0.85))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 2)
        }
        .scaleEffect(isSelected ? 1.05 : depthScale)
        .opacity(isSelected ? 1 : depthOpacity)
        .offset(y: cylinderYOffset)
        .rotation3DEffect(.degrees(depthRotation), axis: (x: 1, y: 0, z: 0), perspective: 0.8)
        .shadow(color: isSelected ? payoutColor.opacity(0.45) : .clear, radius: 16, y: 4)
        .saturation(isLanded && !isSelected ? 0.55 : 1.0)
        .animation(.spring(response: 0.34, dampingFraction: 0.55), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isLanded)
    }
}

#Preview("Focus Unlock Slot") {
    FocusUnlockSlotView(games: TrainingGameCatalog.focusUnlockGames) { _ in }
}
