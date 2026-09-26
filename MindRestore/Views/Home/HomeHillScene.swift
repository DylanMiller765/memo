import SwiftUI

/// Memo's world behind Home: the twilight hill, the ground below it, and the
/// tier's weather (fireflies when charged, dimmed when low, rain when neglected).
struct HomeHillScene: View {
    let tier: HomeTier
    /// Where the hill crest should sit, measured from the top of the safe area.
    /// Home passes the line under Memo's feet so he stands on the hill on every device.
    var crestFromSafeTop: CGFloat = 219

    /// The grassy crest's height as a fraction of the hill image.
    private static let crestFraction: CGFloat = 0.505

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRain: Bool { if case .rain = tier { return true } else { return false } }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let imageHeight = width * 1672 / 941
            let imageOffset = geo.safeAreaInsets.top + crestFromSafeTop - imageHeight * Self.crestFraction
            ZStack(alignment: .top) {
                ground
                world
                    .frame(width: width, height: imageHeight)
                    .offset(y: imageOffset)

                if isRain {
                    // Grey fog over the sky and hill that fades out before the ground (no seam).
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color(red: 0.275, green: 0.294, blue: 0.314).opacity(0.35), location: 0.55),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: imageHeight * 0.75)
                    if !reduceMotion {
                        RainLayer()
                            .frame(height: imageHeight * 0.62)
                            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                    }
                }

                if tier == .glow, !reduceMotion {
                    FireflyLayer()
                        .frame(width: width, height: imageHeight * 0.6)
                        .offset(y: imageOffset)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: tier)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var ground: some View {
        LinearGradient(
            colors: isRain
                ? [Color(red: 0.118, green: 0.133, blue: 0.145), Color(red: 0.094, green: 0.106, blue: 0.114)]
                : [Color(red: 0, green: 0.169, blue: 0.196), Color(red: 0, green: 0.133, blue: 0.165)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var world: some View {
        Image("paywall-twilight-hill-bg")
            .resizable()
            .scaledToFit()
            .saturation(saturation)
            .brightness(isRain ? -0.25 : 0)
            .overlay {
                if tier == .dim { Color.black.opacity(0.15) }
            }
            .overlay {
                if tier == .glow {
                    RadialGradient(
                        colors: [Color.white.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.26, y: 0.1),
                        startRadius: 0,
                        endRadius: 130
                    )
                }
            }
            .overlay(alignment: .bottom) {
                // Blend the image's last rows into the ground (matters most for rain's grey ground).
                LinearGradient(colors: [.clear, isRain ? Color(red: 0.118, green: 0.133, blue: 0.145) : Color(red: 0, green: 0.161, blue: 0.192)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
    }

    private var saturation: Double {
        switch tier {
        case .rain: return 0.1
        case .dim: return 0.55
        case .calm, .glow: return 1
        }
    }
}

// MARK: - Weather

/// Seeded 0..<1 value so streaks and fireflies keep their places between frames.
private func seeded(_ index: Int, _ salt: Double) -> Double {
    let v = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
    return v - v.rounded(.down)
}

private struct RainLayer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let span = size.height + 40
                var streaks = Path()
                for i in 0..<70 {
                    let x = seeded(i, 1) * (size.width + 20)
                    let y = (t * 520 + seeded(i, 2) * span).truncatingRemainder(dividingBy: span) - 20
                    streaks.move(to: CGPoint(x: x, y: y))
                    streaks.addLine(to: CGPoint(x: x - 3, y: y + 14))
                }
                ctx.stroke(streaks, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }
}

private struct FireflyLayer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let color = Color(red: 1, green: 0.953, blue: 0.69) // #FFF3B0

                // Fireflies drifting over the hill.
                for i in 0..<8 {
                    let cx = (0.1 + seeded(i, 3) * 0.8) * size.width
                    let cy = (0.45 + seeded(i, 4) * 0.5) * size.height
                    let x = cx + 18 * sin(t * (0.35 + seeded(i, 5) * 0.3) + seeded(i, 6) * 6.28)
                    let y = cy + 10 * sin(t * (0.5 + seeded(i, 7) * 0.3) * 2 + seeded(i, 8) * 6.28)
                    let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.7 + seeded(i, 9) * 6.28))
                    ctx.opacity = pulse
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)), with: .color(color.opacity(0.22)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(color))
                }

                // A few twinkling stars in the sky.
                for i in 0..<5 {
                    let x = (0.08 + seeded(i, 10) * 0.84) * size.width
                    let y = (0.03 + seeded(i, 11) * 0.22) * size.height
                    ctx.opacity = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * 2.2 + seeded(i, 12) * 6.28))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(.white))
                }
            }
        }
    }
}

#Preview("Glow") { HomeHillScene(tier: .glow) }
#Preview("Calm") { HomeHillScene(tier: .calm) }
#Preview("Dim") { HomeHillScene(tier: .dim) }
#Preview("Rain") { HomeHillScene(tier: .rain(days: 2)) }
