import SwiftUI

/// The first time a game opens: its Train-tab logo, name, one line on what it
/// tests, how to play in three steps, and the app's white Play button. Every
/// game uses this layout so the six intros read as one family.
struct GameIntro: View {
    let game: UnlockGame
    let subtitle: String
    let steps: [(icon: String, text: String)]
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            hero
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 8) {
                ClimbHeadline(text: BoardUnit.forGame(game).gameName, size: 34)
                Text(subtitle)
                    .font(.brand(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            stepList
                .padding(.top, 28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            Spacer(minLength: 16)
            ChunkyButton(title: "Play", systemImage: "play.fill", action: onStart)
                .accessibilityHint("Starts the game")
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: OBLayout.contentMaxWidth + 44)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82).delay(0.05)) { appeared = true }
        }
    }

    /// The Train-tab logo, big, as a sticker with a soft glow in its own color.
    private var hero: some View {
        let size: CGFloat = 116
        return GameGlyph(game: game, size: size)
            .stickerOutline(3)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(ClimbColor.ink).offset(y: 6))
            .background(Circle().fill(GameGlyph.palette(game).0).frame(width: size * 2.2, height: size * 2.2).blur(radius: 50))
    }

    /// One quiet card: each step gets a small tile in the game's colors, split by hairlines.
    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 64)
                }
                HStack(spacing: 14) {
                    Image(systemName: step.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [GameGlyph.palette(game).0, GameGlyph.palette(game).1], startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        )
                    Text(step.text)
                        .font(.brand(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}
