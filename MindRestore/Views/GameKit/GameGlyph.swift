import SwiftUI

struct GameGlyph: View {
    let game: UnlockGame
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(base)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            content
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var base: LinearGradient {
        let pair = Self.palette(game)
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .top, endPoint: .bottom)
    }

    /// Top and bottom of each game's tile, shared with the intro's step icons.
    static func palette(_ game: UnlockGame) -> (Color, Color) {
        switch game {
        case .visualMemory: (Color(red: 0.17, green: 0.23, blue: 0.53), Color(red: 0.11, green: 0.15, blue: 0.38))
        case .numberMemory: (Color(red: 0.05, green: 0.30, blue: 0.29), Color(red: 0.03, green: 0.19, blue: 0.19))
        case .chimpTest: (Color(red: 0.35, green: 0.25, blue: 0.03), Color(red: 0.23, green: 0.16, blue: 0.01))
        case .mathSprint: (Color(red: 0.24, green: 0.25, blue: 0.37), Color(red: 0.14, green: 0.15, blue: 0.25))
        case .colorMatch: (Color(red: 0.25, green: 0.12, blue: 0.35), Color(red: 0.15, green: 0.07, blue: 0.22))
        case .reactionTime: (Color(red: 0.55, green: 0.13, blue: 0.10), Color(red: 0.07, green: 0.47, blue: 0.24))
        }
    }

    @ViewBuilder private var content: some View {
        let s = size
        switch game {
        case .visualMemory:
            let lit: Set<Int> = [1, 3, 8]
            Grid(horizontalSpacing: s * 0.06, verticalSpacing: s * 0.06) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow { ForEach(0..<3, id: \.self) { c in
                        RoundedRectangle(cornerRadius: s * 0.06)
                            .fill(lit.contains(r * 3 + c) ? Color(red: 0.62, green: 0.72, blue: 1) : .white.opacity(0.14))
                            .frame(width: s * 0.2, height: s * 0.2)
                    } }
                }
            }
        case .numberMemory:
            Text("482").font(HeroNumber.font(s * 0.34)).foregroundStyle(Color(red: 0.5, green: 0.9, blue: 0.82))
        case .chimpTest:
            Grid(horizontalSpacing: s * 0.08, verticalSpacing: s * 0.08) {
                GridRow { chimpCell("1"); chimpCell(nil) }
                GridRow { chimpCell(nil); chimpCell("2") }
            }
        case .mathSprint:
            (Text("7").foregroundStyle(OB.fg) + Text("×").foregroundStyle(Color(red: 0.56, green: 0.69, blue: 1)) + Text("8").foregroundStyle(OB.fg))
                .font(HeroNumber.font(s * 0.32))
        case .colorMatch:
            Text("RED").font(HeroNumber.font(s * 0.3)).foregroundStyle(InkColor.green.color)
        case .reactionTime:
            Image(systemName: "bolt.fill").font(.system(size: s * 0.42, weight: .black)).foregroundStyle(.white)
        }
    }

    private func chimpCell(_ label: String?) -> some View {
        RoundedRectangle(cornerRadius: size * 0.08)
            .fill(label == nil ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), OB.amber], startPoint: .top, endPoint: .bottom)))
            .frame(width: size * 0.3, height: size * 0.3)
            .overlay(Text(label ?? "").font(HeroNumber.font(size * 0.2)).foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0)))
    }
}

extension UnlockGame {
    /// The bright accent of the game's glyph — the slot window tints to it on landing.
    var glyphTint: Color {
        switch self {
        case .visualMemory: Color(red: 0.62, green: 0.72, blue: 1)
        case .numberMemory: Color(red: 0.5, green: 0.9, blue: 0.82)
        case .chimpTest: Color(red: 1, green: 0.85, blue: 0.54)
        case .mathSprint: Color(red: 0.56, green: 0.69, blue: 1)
        case .colorMatch: Color(red: 0.72, green: 0.45, blue: 1)
        case .reactionTime: Color(red: 1, green: 0.35, blue: 0.29)
        }
    }
}

extension UnlockGame {
    /// Best score in the game's own units (ms for Reaction Time), or nil if never played.
    @MainActor var personalBest: Int? {
        let stored = PersonalBestTracker.shared.best(for: exerciseType)
        guard stored > 0 else { return nil }
        // Reaction Time is stored inverted (1000 − ms) so higher is better in the tracker.
        if self == .reactionTime { return stored < 1000 ? 1000 - stored : nil }
        return stored
    }

    /// "LV 7", "9 digits", "8 numbers", "16", "288ms".
    func scoreText(_ score: Int) -> String {
        switch self {
        case .visualMemory: "LV \(score)"
        case .numberMemory: "\(score) digits"
        case .chimpTest: "\(score) numbers"
        case .mathSprint, .colorMatch: "\(score)"
        case .reactionTime: "\(score)ms"
        }
    }
}
