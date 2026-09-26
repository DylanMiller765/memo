import SwiftUI

/// The big outlined "67%", a chunky charge bar, and one line of copy.
struct HomeChargeMeter: View {
    let percent: Int
    let tier: HomeTier
    let line: String
    /// When set, the number and bar count up from this value (the return payoff).
    var animateFrom: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Int?

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)      // #0B1B22
    private static let rainInk = Color(red: 0.067, green: 0.078, blue: 0.09)   // #111417
    private static let outline: [CGSize] = [
        CGSize(width: 3, height: 0), CGSize(width: -3, height: 0),
        CGSize(width: 0, height: 3), CGSize(width: 0, height: -3),
        CGSize(width: 2, height: 2), CGSize(width: -2, height: -2),
        CGSize(width: 2, height: -2), CGSize(width: -2, height: 2),
    ]

    private var shown: Int { displayed ?? percent }
    private var isRain: Bool { if case .rain = tier { return true } else { return false } }

    var body: some View {
        VStack(spacing: 10) {
            number
            bar
            Text(line)
                .font(.brand(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memo is \(percent) percent charged. \(line)")
        .onAppear(perform: startPayoff)
        .onChange(of: animateFrom) { _, _ in startPayoff() }
        .onChange(of: percent) { _, _ in if animateFrom == nil { displayed = nil } }
    }

    private func label(_ color: Color) -> Text {
        (Text("\(shown)").font(.brand(size: 66, weight: .heavy))
            + Text("%").font(.brand(size: 32, weight: .heavy)))
            .foregroundColor(color)
    }

    private var number: some View {
        ZStack {
            ForEach(Array(Self.outline.enumerated()), id: \.offset) { _, offset in
                label(isRain ? Self.rainInk : Self.ink).offset(offset)
            }
            label(.white)
        }
        .contentTransition(.numericText(value: Double(shown)))
        .shadow(color: .black.opacity(0.25), radius: 0, y: 6)
        .lineLimit(1)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                if shown > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: shown <= 33
                                ? [Color(red: 1, green: 0.878, blue: 0.541), Color(red: 0.949, green: 0.663, blue: 0.231)]
                                : [Color(red: 0.851, green: 1, blue: 0.945), Color(red: 0.482, green: 0.89, blue: 0.776)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: max(18, geo.size.width * CGFloat(shown) / 100))
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Self.ink.opacity(0.7), lineWidth: 2))
        }
        .frame(height: 18)
    }

    private func startPayoff() {
        guard let from = animateFrom, from < percent, !reduceMotion else {
            displayed = nil
            return
        }
        displayed = from
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.8)) { displayed = percent }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        HomeChargeMeter(percent: 100, tier: .glow, line: "Fully charged. See you tomorrow.")
        HomeChargeMeter(percent: 67, tier: .calm, line: "1 more game for 100%.", animateFrom: 33)
        HomeChargeMeter(percent: 33, tier: .dim, line: "2 more games to charge Memo up.")
        HomeChargeMeter(percent: 0, tier: .rain(days: 2), line: "Memo's been rained on for 2 days. Play 1 game.")
    }
    .padding(20)
    .background(Color(red: 0, green: 0.17, blue: 0.2))
}
