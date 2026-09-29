import SwiftUI

// The end of a Train-tab game: onboarding's "You'd place" board with the real
// score posted. One line for the score (and a sticker on a new best), the weekly board climbing to
// your rank, then Play again.

struct GameResultSummary {
    var game: UnlockGame
    var score: Int
    var isNewBest: Bool
}

struct GameResultScreen: View {
    let summary: GameResultSummary
    let board: OnboardingBoardState
    var onSignIn: () -> Void = {}
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private var unit: BoardUnit { BoardUnit.forGame(summary.game) }

    private var isPractice: Bool {
        if case .practice = board { return true }
        return false
    }

    /// Only a real Game Center board means the score was posted.
    private var isPosted: Bool {
        if case .loaded = board { return true }
        return false
    }

    var body: some View {
        GeometryReader { geo in
            // SE-sized screens (under ~680pt inside the game) get the shorter board.
            let compact = geo.size.height < 680
            VStack(spacing: 0) {
                scoreLine
                    .padding(.top, compact ? 6 : 14)
                    .padding(.bottom, compact ? 12 : 22)
                if summary.score > 0 {
                    OnboardingLeaderboardClimb(board: board, level: summary.score, compact: compact,
                                               unit: unit, isPosted: isPosted, onPlayAgain: onPlayAgain)
                } else {
                    VStack(spacing: 8) {
                        ClimbHeadline(text: "Not on the board yet.", size: compact ? 28 : 34)
                        Text("Play again to get on this week's board.")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                    Spacer(minLength: 8)
                }
                if isPractice, summary.score > 0 {
                    Button("Sign in to Game Center", action: onSignIn)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(ClimbColor.mint)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
                buttons
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: OBLayout.contentMaxWidth + 44)
            .frame(maxWidth: .infinity)
        }
    }

    private var scoreLine: some View {
        HStack(spacing: 10) {
            GameGlyph(game: summary.game, size: 34)
            Text(unit.capitalized(summary.score))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            if summary.isNewBest {
                Label("New best!", systemImage: "trophy.fill")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ClimbColor.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(ClimbColor.amber))
                    .overlay(Capsule().strokeBorder(ClimbColor.ink, lineWidth: 2.5))
                    .background(Capsule().fill(ClimbColor.ink).offset(y: 3))
                    .rotationEffect(.degrees(-4))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ChunkyButton(title: "Play again", systemImage: "arrow.counterclockwise", action: onPlayAgain)
                if summary.isNewBest { ResultShareButton(summary: summary) }
            }
            Button {
                onDone()
                ReviewPromptService.presentPendingIfAny()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Feeds the result this week's Game Center board (Memo's rivals when signed out or empty).
struct LiveGameEnd<Content: View>: View {
    let game: UnlockGame?
    @ViewBuilder let content: (_ board: OnboardingBoardState, _ signIn: @escaping () -> Void) -> Content

    @Environment(GameCenterService.self) private var gameCenter
    @State private var board: OnboardingBoardState = .loading

    var body: some View {
        content(board, { gameCenter.authenticate() })
            .task(id: gameCenter.isAuthenticated) { if let game { board = await GameEndData.board(for: game, gameCenter: gameCenter) } }
    }
}

enum GameEndData {
    /// This week's Game Center board, or Memo's rivals when signed out or empty.
    @MainActor static func board(for game: UnlockGame, gameCenter: GameCenterService) async -> OnboardingBoardState {
        guard gameCenter.isAuthenticated else { return .practice }
        let entries = await loadWeeklyBoard(for: game, gameCenter: gameCenter)
        return entries.isEmpty ? .practice : .loaded(entries: entries, totalPlayers: entries.count)
    }
}

// MARK: - Share

/// On a new best: a story-sized card with the score, shared as an image.
private struct ResultShareButton: View {
    let summary: GameResultSummary
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview("New best in \(BoardUnit.forGame(summary.game).gameName)", image: image)) { label }
            } else {
                label.opacity(0.5)
            }
        }
        .task { render() }
    }

    private var label: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1.5))
            .accessibilityLabel("Share your new best")
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: ResultShareCard(summary: summary))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}

/// The story-sized card that gets shared.
private struct ResultShareCard: View {
    let summary: GameResultSummary

    var body: some View {
        let unit = BoardUnit.forGame(summary.game)
        VStack(spacing: 14) {
            GameGlyph(game: summary.game, size: 96)
                .stickerOutline(3)
            Text("NEW BEST")
                .font(.system(size: 16, weight: .black, design: .rounded)).tracking(2)
                .foregroundStyle(OB.amber)
                .padding(.top, 10)
            Text(unit.capitalized(summary.score))
                .font(HeroNumber.font(64))
                .foregroundStyle(LinearGradient.hero(OB.amber))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(unit.gameName)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text("memo")
                .font(.brand(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 30)
        }
        .padding(.horizontal, 24)
        .frame(width: 360, height: 640)
        .background(RadialGradient(colors: [Color(red: 0.25, green: 0.18, blue: 0.05), OB.bg], center: .center, startRadius: 0, endRadius: 420))
    }
}
