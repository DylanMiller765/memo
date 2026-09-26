import SwiftUI
import FamilyControls
import ManagedSettings

// MARK: - Shared bits

/// Loud, tilted signage type used for DENIED / FREE PASS / EARNED moments.
struct SignageText: View {
    let text: String
    let colors: [Color]
    var size: CGFloat = 56

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded).italic())
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .shadow(color: (colors.last ?? OB.amber).opacity(0.8), radius: 18)
            .rotationEffect(.degrees(-4))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

extension UnlockGame {
    var leaderboardCategory: LeaderboardCategory {
        switch self {
        case .visualMemory: .visualMemory
        case .numberMemory: .numberMemory
        case .chimpTest: .chimpTest
        case .mathSprint: .mathSprint
        case .colorMatch: .colorMatch
        case .reactionTime: .reactionTime
        }
    }

    /// Singular/plural unit for "N short" lines.
    func shortfallText(_ distance: Int) -> String {
        switch self {
        case .visualMemory: "\(distance) \(distance == 1 ? "level" : "levels") short"
        case .numberMemory: "\(distance) \(distance == 1 ? "digit" : "digits") short"
        case .chimpTest: "\(distance) \(distance == 1 ? "number" : "numbers") short"
        case .mathSprint, .colorMatch: "\(distance) correct short"
        case .reactionTime: "\(distance)ms too slow"
        }
    }

    var fallbackFact: String {
        switch self {
        case .visualMemory: "most people reach LV 7"
        case .numberMemory: "the average is 7 digits"
        case .chimpTest: "chimps average 7"
        case .mathSprint: "20 is elite"
        case .colorMatch: "26 is elite"
        case .reactionTime: "the average is about 270ms"
        }
    }
}

private struct BlockedAppName: View {
    var body: some View {
        if let token = BlockedAppTokenStore.load() {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text("the feed")
        }
    }
}

private func loadWeeklyBoard(for game: UnlockGame, gameCenter: GameCenterService) async -> [LeaderboardEntryData] {
    let result = await gameCenter.loadLeaderboardEntries(
        category: game.leaderboardCategory,
        timeFilter: .thisWeek,
        range: NSRange(location: 1, length: 50)
    )
    return result.entries
}

// MARK: - Cash out / keep going

struct CashOutCard: View {
    let run: UnlockRun

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                OnboardingPadlock(isOpen: true, size: 64)
                Text("UNLOCK EARNED")
                    .font(.brand(size: 24, weight: .black))
                    .foregroundStyle(OB.fg)
                HStack(spacing: 12) {
                    Button {
                        Analytics.unlockChoice(game: run.game.rawValue, keepGoing: false)
                        run.cashOut()
                    } label: {
                        Text("Cash out · \(run.liveMinutes) min")
                            .font(.brand(size: 16, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(OB.success))
                    }
                    Button {
                        Analytics.unlockChoice(game: run.game.rawValue, keepGoing: true)
                        run.keepGoing()
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 5) {
                                Text("Keep going")
                                Image(systemName: "flame.fill").font(.system(size: 14, weight: .bold))
                            }
                            .font(.brand(size: 16, weight: .heavy))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Keep going")
                            Text("up to 15 min + rank")
                                .font(.brand(size: 11, weight: .bold))
                                .opacity(0.8)
                        }
                        .foregroundStyle(Color(red: 0.16, green: 0.06, blue: 0))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [OB.amber, OB.coral], startPoint: .top, endPoint: .bottom)))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(OB.surface))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear { HapticService.complete() }
    }
}

// MARK: - UNLOCKED

struct UnlockedScreen: View {
    /// nil = FREE PASS (no game, no climb).
    let game: UnlockGame?
    let outcome: UnlockOutcome
    let onDone: () -> Void

    @Environment(GameCenterService.self) private var gameCenter
    @State private var revealed = false
    @State private var showClimb = false
    @State private var board: OnboardingBoardState = .loading

    private var minutes: Int {
        if case .unlocked(let minutes, _, _, _) = outcome { return minutes }
        return 0
    }
    private var score: Int {
        if case .unlocked(_, _, let score, _) = outcome { return score }
        return 0
    }
    private var isPersonalBest: Bool {
        if case .unlocked(_, _, _, let pb) = outcome { return pb }
        return false
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < OBLayout.compactHeight
            ZStack {
                GameBackdrop(glow: game == nil ? Color(red: 0.23, green: 0.16, blue: 0.03) : Color(red: 0.03, green: 0.2, blue: 0.16))
                VStack(spacing: 0) {
                    if game == nil {
                        SignageText(text: "FREE PASS", colors: [Color(red: 1, green: 0.9, blue: 0.6), OB.amber], size: 44)
                            .padding(.top, 40)
                    }
                    if showClimb, let game {
                        OnboardingLeaderboardClimb(board: board, level: max(score, 1), compact: compact, onPlayAgain: {})
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .task { await loadBoard(game) }
                    } else {
                        OnboardingUnlockMoment(minutes: minutes, compact: compact, isLive: true,
                                               intro: game == nil ? "Memo's treat. No game this time." : nil) {
                            revealed = true
                            if game != nil {
                                DispatchQueue.main.asyncAfter(deadline: .now() + (isPersonalBest ? 1.0 : 0.4)) {
                                    withAnimation(.spring(duration: 0.4)) { showClimb = true }
                                }
                            }
                        }
                        .overlay {
                            PraisePop(text: revealed && isPersonalBest ? "NEW BEST +2" : nil, tint: OB.amber)
                        }
                    }
                    Spacer(minLength: 12)
                    if revealed {
                        Button(action: onDone) {
                            Text("Go scroll · \(minutes):00 starts now")
                                .font(.brand(size: 17, weight: .heavy))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(OB.success))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !revealed else { return }
                withAnimation { revealed = true; if game != nil { showClimb = true } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadBoard(_ game: UnlockGame) async {
        let entries = await loadWeeklyBoard(for: game, gameCenter: gameCenter)
        board = entries.isEmpty ? .unavailable : .loaded(entries: entries, totalPlayers: entries.count)
    }
}

// MARK: - DENIED

struct DeniedScreen: View {
    let game: UnlockGame
    let score: Int
    let distance: Int
    let denials: Int
    let onTryAgain: () -> Void
    let onStayOff: () -> Void
    let onNeedIt: () -> Void

    @Environment(GameCenterService.self) private var gameCenter
    @State private var rivalLine: String?
    @State private var shake: CGFloat = 0

    var body: some View {
        ZStack {
            GameBackdrop(glow: OB.coral.opacity(0.35))
            VStack(spacing: 14) {
                Spacer(minLength: 20)
                ZStack(alignment: .bottomTrailing) {
                    Image("mascot-locked-sad")
                        .resizable().scaledToFit()
                        .frame(width: 150, height: 150)
                    BlockedAppIcon(size: 64, showLock: true, unlocked: false)
                        .modifier(OnboardingShakeEffect(travel: shake))
                        .offset(x: 18, y: 8)
                }
                SignageText(text: "DENIED", colors: [Color(red: 1, green: 0.62, blue: 0.55), OB.coral])
                Text(game.shortfallText(distance))
                    .font(.brand(size: 17, weight: .bold))
                    .foregroundStyle(OB.fg)
                Text(rivalLine ?? game.fallbackFact)
                    .font(.brand(size: 14, weight: .semibold))
                    .foregroundStyle(OB.fg2)
                    .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: 12) {
                    Button(action: onTryAgain) {
                        Text("Try again")
                            .font(.brand(size: 17, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(OB.accent))
                    }
                    Button(action: onStayOff) {
                        HStack(spacing: 4) {
                            Text("Stay off")
                            BlockedAppName()
                        }
                        .font(.brand(size: 15, weight: .bold))
                        .foregroundStyle(OB.fg2)
                        .frame(minHeight: 44)
                    }
                    if denials >= UnlockRulebook.escapeHatchAfterDenials {
                        Button(action: onNeedIt) {
                            Text("I really need it")
                                .font(.brand(size: 14, weight: .semibold))
                                .foregroundStyle(OB.fg3)
                                .frame(minHeight: 36)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            HapticService.wrong()
            withAnimation(.linear(duration: 0.5)) { shake = 3 }
        }
        .task { await loadRival() }
    }

    private func loadRival() async {
        let entries = await loadWeeklyBoard(for: game, gameCenter: gameCenter)
        let better = entries.filter { game.lowerIsBetter ? ($0.score < score && $0.score > 0) : $0.score > score }
        let nearest = game.lowerIsBetter ? better.max(by: { $0.score < $1.score }) : better.min(by: { $0.score < $1.score })
        if let nearest {
            let value = game == .reactionTime ? "\(nearest.score)ms" : "\(nearest.score)"
            rivalLine = "@\(nearest.username) made it to \(value)"
        }
    }
}

// MARK: - Escape hatch

struct EscapeHatchScreen: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var start = Date()
    @State private var fired = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = max(0, UnlockRulebook.escapeHatchCountdownSeconds - Int(context.date.timeIntervalSince(start)))
            ZStack {
                GameBackdrop()
                VStack(spacing: 14) {
                    Spacer()
                    Text("\(left)")
                        .font(HeroNumber.font(96))
                        .foregroundStyle(LinearGradient.hero(Color(red: 0.62, green: 0.72, blue: 1)))
                        .contentTransition(.numericText(countsDown: true))
                    Text("Taking a breath first.")
                        .font(.brand(size: 20, weight: .heavy))
                        .foregroundStyle(OB.fg)
                    Text("\(UnlockRulebook.escapeHatchMinutes) minutes, then it locks again.")
                        .font(.brand(size: 15, weight: .semibold))
                        .foregroundStyle(OB.fg2)
                    Spacer()
                    Button("Never mind", action: onCancel)
                        .font(.brand(size: 15, weight: .bold))
                        .foregroundStyle(OB.fg3)
                        .padding(.bottom, 20)
                }
            }
            .onChange(of: left) { _, value in
                if value == 0, !fired {
                    fired = true
                    onComplete()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
