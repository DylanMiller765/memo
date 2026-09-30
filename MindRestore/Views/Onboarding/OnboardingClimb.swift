import SwiftUI

// MARK: - The climb
//
// The concise onboarding is one walk up Memo's hill: the sky brightens from
// night to sunrise as the user moves through it, and each page marks where
// the grassy crest should sit (Memo's feet, the slot booth, the board) with
// `.climbCrest()`. OnboardingView reads that mark and draws the hill behind
// everything, so the scene carries across the progress header too.

enum ClimbColor {
    static let mint = Color(red: 0.482, green: 0.89, blue: 0.776)   // #7BE3C6
    static let amber = Color(red: 1, green: 0.827, blue: 0.42)      // #FFD36B
    static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)   // #0B1B22, the sticker outline
}

/// How far up the hill the user is. Each step is a brighter sky.
enum ClimbSky: Int {
    case night, twilight, predawn, sunrise
}

/// How pages tell the onboarding where the hill's crest goes and how bright
/// the sky is. A closure, not a PreferenceKey: observing preferences on the
/// onboarding root froze the pages' entrance animations.
struct ClimbReporter {
    static let space = "onboarding-climb"
    var crest: (CGFloat?) -> Void = { _ in }
    var sky: (ClimbSky?) -> Void = { _ in }
}

private struct ClimbReporterKey: EnvironmentKey {
    static let defaultValue = ClimbReporter()
}

extension EnvironmentValues {
    var climbReporter: ClimbReporter {
        get { self[ClimbReporterKey.self] }
        set { self[ClimbReporterKey.self] = newValue }
    }
}

extension View {
    /// Puts the hill's crest on this view's bottom edge (or `below` points under it).
    func climbCrest(below: CGFloat = 0) -> some View {
        modifier(ClimbCrestMark(below: below))
    }

    /// `.climbCrest()` only when `enabled` (shared views used outside onboarding).
    @ViewBuilder
    func climbCrestIf(_ enabled: Bool) -> some View {
        if enabled { climbCrest() } else { self }
    }

    /// Brightens (or dims) the sky while this view is on screen.
    func climbSky(_ sky: ClimbSky?) -> some View {
        modifier(ClimbSkyMark(sky: sky))
    }

    /// Flat sticker outline: a white rim on every side and a dark drop below.
    func stickerOutline(_ width: CGFloat = 2.5) -> some View {
        self
            .shadow(color: .white, radius: 0, x: width, y: 0)
            .shadow(color: .white, radius: 0, x: -width, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: width)
            .shadow(color: .white, radius: 0, x: 0, y: -width)
            .shadow(color: ClimbColor.ink.opacity(0.85), radius: 0, x: 0, y: width + 2)
    }
}

private struct ClimbCrestMark: ViewModifier {
    var below: CGFloat = 0
    @Environment(\.climbReporter) private var reporter

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                let y = geo.frame(in: .named(ClimbReporter.space)).maxY + below
                Color.clear
                    .onAppear { reporter.crest(y) }
                    .onChange(of: y) { _, newY in reporter.crest(newY) }
            }
        )
    }
}

private struct ClimbSkyMark: ViewModifier {
    let sky: ClimbSky?
    @Environment(\.climbReporter) private var reporter

    func body(content: Content) -> some View {
        content
            .onAppear { reporter.sky(sky) }
            .onChange(of: sky) { _, newSky in reporter.sky(newSky) }
    }
}

/// Memo's hill behind the onboarding, with the crest at `crestY` (points from
/// the top of the safe area) and the sky for how far the user has climbed.
struct OnboardingClimbBackdrop: View {
    let sky: ClimbSky
    /// nil until the page reports its crest; then the hill sits a little below center.
    let crestY: CGFloat?

    /// The grassy crest's height as a fraction of the hill image (same art as Home).
    private static let crestFraction: CGFloat = 0.505
    /// Where the moon sits in the same art.
    private static let moonFraction: CGFloat = 0.105

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let imageHeight = width * 1672 / 941
            let crest = crestY ?? geo.size.height * 0.62
            let imageOffset = geo.safeAreaInsets.top + crest - imageHeight * Self.crestFraction
            let imageBottom = imageOffset + imageHeight
            // The moon is painted into the hill art. When the hill moves up, it lands behind
            // the clock or the headline; cover it there so it never sits behind text.
            let moonY = imageOffset + imageHeight * Self.moonFraction
            let hidesMoon = moonY < geo.safeAreaInsets.top + 320
            ZStack(alignment: .top) {
                // Ground below the art: starts at the art's last row so there's no seam.
                LinearGradient(
                    colors: [Color(red: 1 / 255, green: 43 / 255, blue: 52 / 255), Color(red: 0, green: 0.133, blue: 0.165)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Night darkens the whole scene, so the ground below the art too (no seam).
                .overlay(Color.black.opacity(sky == .night ? 0.22 : 0))
                .frame(height: max(1, geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom - imageBottom))
                .offset(y: imageBottom - 1)

                // The art starts below the top of the screen when the crest sits
                // low; fill that band with the sky's top color so it never seams.
                ZStack {
                    Self.topColor(.night).opacity(sky == .night ? 1 : 0)
                    Self.topColor(.twilight).opacity(sky == .twilight ? 1 : 0)
                    Self.topColor(.predawn).opacity(sky == .predawn ? 1 : 0)
                    Self.topColor(.sunrise).opacity(sky == .sunrise ? 1 : 0)
                }
                .frame(height: max(0, imageOffset) + 2)

                world(width: width, hidesMoon: hidesMoon)
                    .frame(width: width, height: imageHeight)
                    .offset(y: imageOffset)
            }
            .frame(width: width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.7), value: sky)
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: crestY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func world(width: CGFloat, hidesMoon: Bool) -> some View {
        let scale = width / 390
        return ZStack {
            Image("paywall-twilight-hill-bg")
                .resizable()
                .scaledToFit()

            // Paints over the moon with the sky around it (the same patch sunrise uses).
            GeometryReader { g in
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.024, green: 0.106, blue: 0.41), location: 0.62),
                        .init(color: Color(red: 0.024, green: 0.106, blue: 0.41).opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 32 * scale
                )
                .frame(width: 64 * scale, height: 64 * scale)
                .position(x: g.size.width * 0.24, y: g.size.height * Self.moonFraction)
            }
            .opacity(hidesMoon ? 1 : 0)

            // Night: the same scene, deeper.
            ZStack {
                Color.black.opacity(0.22)
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.01, green: 0.02, blue: 0.12).opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .opacity(sky == .night ? 1 : 0)

            // Pre-dawn: a pink band rises behind the trees.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.35, green: 0.27, blue: 0.67).opacity(0.18), location: 0),
                    .init(color: Color(red: 0.59, green: 0.35, blue: 0.75).opacity(0.28), location: 0.26),
                    .init(color: Color(red: 1, green: 0.55, blue: 0.63).opacity(0.55), location: 0.41),
                    .init(color: Color(red: 1, green: 0.59, blue: 0.51).opacity(0), location: 0.50),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(sky == .predawn ? 1 : 0)

            // Sunrise: the moon sets, the sky warms, the sun glows behind the crest.
            ZStack {
                GeometryReader { g in
                    RadialGradient(
                        stops: [
                            .init(color: Color(red: 0.024, green: 0.106, blue: 0.41), location: 0.62),
                            .init(color: Color(red: 0.024, green: 0.106, blue: 0.41).opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 32 * scale
                    )
                    .frame(width: 64 * scale, height: 64 * scale)
                    .position(x: g.size.width * 0.24, y: g.size.height * 0.105)
                }
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.43, green: 0.47, blue: 0.86).opacity(0.45), location: 0),
                        .init(color: Color(red: 0.75, green: 0.51, blue: 0.82).opacity(0.45), location: 0.22),
                        .init(color: Color(red: 1, green: 0.61, blue: 0.51).opacity(0.8), location: 0.37),
                        .init(color: Color(red: 1, green: 0.78, blue: 0.51).opacity(0.65), location: 0.46),
                        .init(color: Color(red: 1, green: 0.78, blue: 0.51).opacity(0), location: 0.51),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                GeometryReader { g in
                    RadialGradient(
                        stops: [
                            .init(color: Color(red: 1, green: 0.94, blue: 0.75).opacity(0.95), location: 0),
                            .init(color: Color(red: 1, green: 0.78, blue: 0.47).opacity(0.55), location: 0.45),
                            .init(color: Color(red: 1, green: 0.67, blue: 0.47).opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 170 * scale
                    )
                    .frame(width: 340 * scale, height: 340 * scale)
                    .scaleEffect(x: 1, y: 110.0 / 170.0)
                    .position(x: g.size.width * 0.5, y: g.size.height * 0.49)
                    .blendMode(.screen)
                }
            }
            .opacity(sky == .sunrise ? 1 : 0)
        }
    }

    /// The color at the very top of the hill art under each sky.
    static func topColor(_ sky: ClimbSky) -> Color {
        switch sky {
        case .night: return Color(red: 2 / 255, green: 6 / 255, blue: 51 / 255)
        case .twilight: return Color(red: 2 / 255, green: 10 / 255, blue: 80 / 255)
        case .predawn: return Color(red: 18 / 255, green: 21 / 255, blue: 96 / 255)
        case .sunrise: return Color(red: 51 / 255, green: 60 / 255, blue: 143 / 255)
        }
    }
}

// MARK: - Type

/// A white headline with the dark sticker outline, wrapping like OBHeadline.
struct ClimbHeadline: View {
    let text: String
    var size: CGFloat = 32
    var alignment: TextAlignment = .center

    private var outline: CGFloat { max(2, size / 11) }

    var body: some View {
        let d = outline
        let offsets = [CGSize(width: d, height: 0), CGSize(width: -d, height: 0), CGSize(width: 0, height: d), CGSize(width: 0, height: -d),
                       CGSize(width: d * 0.72, height: d * 0.72), CGSize(width: -d * 0.72, height: -d * 0.72),
                       CGSize(width: d * 0.72, height: -d * 0.72), CGSize(width: -d * 0.72, height: d * 0.72),
                       CGSize(width: 0, height: d * 1.7)]
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).foregroundStyle(ClimbColor.ink).offset(offsets[i])
            }
            Text(text).foregroundStyle(.white)
        }
        .font(.brand(size: size, weight: .heavy))
        .tracking(-0.4)
        .lineSpacing(-2)
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Body copy that stays readable over the sky and the grass.
struct ClimbBodyText: View {
    let text: String
    var size: CGFloat = 16
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .lineSpacing(2)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: Color(red: 0, green: 0.08, blue: 0.12).opacity(0.8), radius: 6)
    }
}

// MARK: - Trail

/// Spin → Play → Unlock → Rank as flags planted up a dotted trail.
struct ClimbTrail: View {
    let current: Int
    var compact = false
    private let labels = ["Spin", "Play", "Unlock", "Rank"]

    var body: some View {
        GeometryReader { geo in
            let rise: CGFloat = compact ? 7 : 10
            let points = labels.indices.map { i -> CGPoint in
                let x = geo.size.width * (CGFloat(i) + 0.5) / CGFloat(labels.count)
                return CGPoint(x: x, y: CGFloat(labels.count - 1 - i) * rise + 26)
            }
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addLines(points)
                }
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 7]))

                ForEach(labels.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        ClimbFlag(state: i < current ? .done : (i == current ? .now : .todo), size: compact ? 24 : 28)
                        Text(labels[i])
                            .font(.system(size: compact ? 11 : 12, weight: i == current ? .heavy : .bold, design: .rounded))
                            .foregroundStyle(i <= current ? Color.white : Color.white.opacity(0.5))
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .fixedSize()
                    }
                    .position(x: points[i].x + 4, y: points[i].y - (compact ? 4 : 6))
                }
            }
        }
        .frame(height: compact ? 58 : 66)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of 4: \(labels[min(current, labels.count - 1)])")
    }
}

struct ClimbFlag: View {
    enum State { case done, now, todo }
    let state: State
    var size: CGFloat = 28

    var body: some View {
        let ink = ClimbColor.ink
        let cloth: Color = state == .done ? ClimbColor.mint : (state == .now ? .white : Color.white.opacity(0.18))
        let line: Color = state == .todo ? Color.white.opacity(0.5) : ink
        Canvas { ctx, canvas in
            ctx.scaleBy(x: canvas.width / 30, y: canvas.height / 34)
            var pole = Path()
            pole.move(to: CGPoint(x: 7, y: 3))
            pole.addLine(to: CGPoint(x: 7, y: 32))
            ctx.stroke(pole, with: .color(state == .todo ? Color.white.opacity(0.45) : ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var flag = Path()
            flag.move(to: CGPoint(x: 8, y: 4))
            flag.addCurve(to: CGPoint(x: 19, y: 4), control1: CGPoint(x: 12, y: 2), control2: CGPoint(x: 15, y: 6))
            flag.addCurve(to: CGPoint(x: 27, y: 4), control1: CGPoint(x: 23, y: 2), control2: CGPoint(x: 25, y: 3))
            flag.addLine(to: CGPoint(x: 27, y: 16))
            flag.addCurve(to: CGPoint(x: 19, y: 16), control1: CGPoint(x: 25, y: 15), control2: CGPoint(x: 23, y: 14))
            flag.addCurve(to: CGPoint(x: 8, y: 16), control1: CGPoint(x: 15, y: 18), control2: CGPoint(x: 12, y: 14))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(cloth))
            ctx.stroke(flag, with: .color(line), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            if state == .done {
                var check = Path()
                check.move(to: CGPoint(x: 13, y: 9.5))
                check.addLine(to: CGPoint(x: 15.6, y: 12.1))
                check.addLine(to: CGPoint(x: 21, y: 6.8))
                ctx.stroke(check, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size * 30 / 34, height: size)
        .modifier(ClimbFlagOutline(active: state != .todo))
        .shadow(color: state == .now ? .white.opacity(0.6) : .clear, radius: 8)
    }
}

private struct ClimbFlagOutline: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.stickerOutline(2) } else { content }
    }
}

// MARK: - Memo on the hill

/// Memo's Rive mascot standing on the crest, with a soft shadow under his feet.
struct ClimbMemo: View {
    let mood: MascotRiveMood
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.4))
                .frame(width: size * 0.6, height: size * 0.1)
                .blur(radius: 4)
                .offset(y: -size * 0.02)
            RiveMascotView(mood: mood, size: size, playbackPolicy: .continuous)
                .frame(height: size * 0.91)
        }
        .frame(height: size * 0.91)
        .climbCrest()
        .accessibilityHidden(true)
    }
}

// MARK: - Pass + chips

/// The golden trial pass (the slot's FREE PASS, grown up): "7 DAYS FREE".
struct ClimbPassSticker: View {
    let title: String
    var width: CGFloat = 250

    var body: some View {
        let ink = ClimbColor.ink
        let amber = Color(red: 1, green: 0.827, blue: 0.42)
        let height = width * 0.46
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.89, blue: 0.6), amber, Color(red: 0.95, green: 0.71, blue: 0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ink, lineWidth: 3)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink)
                    .frame(width: height * 0.42, height: height * 0.42)
                    .overlay(
                        Image(systemName: "ticket.fill")
                            .font(.system(size: height * 0.2, weight: .bold))
                            .foregroundStyle(amber)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.brand(size: width * 0.095, weight: .heavy))
                        .italic()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("FULL ACCESS PASS")
                        .font(.system(size: width * 0.044, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .lineLimit(1)
                }
                .foregroundStyle(ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .leading) { notch.offset(x: -11) }
        .overlay(alignment: .trailing) { notch.offset(x: 11) }
        .stickerOutline(3)
        .shadow(color: amber.opacity(0.55), radius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), full access pass")
    }

    private var notch: some View {
        Circle()
            .fill(Color(red: 0.17, green: 0.15, blue: 0.31))
            .overlay(Circle().strokeBorder(ClimbColor.ink, lineWidth: 3))
            .frame(width: 22, height: 22)
    }
}

/// White sticker chip: icon + short label.
struct ClimbChip: View {
    let icon: StickerKind
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            StickerIcon(kind: icon, size: 22)
            Text(text)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(ClimbColor.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ClimbColor.ink).offset(y: 4))
        .padding(.bottom, 4)
    }
}

/// Dark glass card with the chunky white rim (boards, choices).
struct ClimbCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.024, green: 0.118, blue: 0.149).opacity(0.86)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ClimbColor.ink, lineWidth: 2.5))
            .background(RoundedRectangle(cornerRadius: 23.5, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2).padding(-2))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ClimbColor.ink).offset(y: 5))
    }
}
