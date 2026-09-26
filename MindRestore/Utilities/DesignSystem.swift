import SwiftUI
import SwiftData
import UIKit

// MARK: - App Colors
// Premium Game Board — warm light bg, clean cards, muted game colors
// Inspired by: NYT Games cleanliness + Apple friendliness + competitive energy

enum AppColors {
    // Adaptive base — cream in light, dark in dark mode
    static let pageBg = Color("PageBg", bundle: nil)
    static let cardSurface = Color("CardSurface", bundle: nil)
    static let cardElevated = Color("CardElevated", bundle: nil)
    static let cardBorder = Color("CardBorder", bundle: nil)
    static let cardBorderDark = Color("CardBorderDark", bundle: nil)

    // Fallbacks for when asset catalog colors aren't found
    static let pageBgLight = Color(red: 0.969, green: 0.961, blue: 0.941)   // #F7F5F0
    static let pageBgDark = Color(red: 0.039, green: 0.039, blue: 0.059)    // #0A0A0F

    // Text — use system .primary/.secondary where possible, these for explicit use
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(red: 0.62, green: 0.60, blue: 0.58)

    // Accent — rich blue (energetic, trustworthy, competitive)
    static let accent = Color(red: 0.29, green: 0.50, blue: 0.90)           // #4A7FE5

    // Functional
    static let error = Color(red: 0.85, green: 0.28, blue: 0.25)
    static let warning = Color(red: 0.90, green: 0.62, blue: 0.15)
    static let chartBlue = Color(red: 0.35, green: 0.55, blue: 0.85)

    // Per-game colors — muted, earthy, sophisticated
    static let teal = Color(red: 0.20, green: 0.60, blue: 0.56)             // sage teal
    static let indigo = Color(red: 0.38, green: 0.36, blue: 0.70)           // muted indigo
    static let coral = Color(red: 0.85, green: 0.40, blue: 0.35)            // dusty coral
    static let coralDeep = Color(red: 0.78, green: 0.22, blue: 0.20)        // danger-escalation red — pairs with coral as a "things got worse" signal
    static let violet = Color(red: 0.55, green: 0.38, blue: 0.75)           // dusty violet
    static let sky = Color(red: 0.35, green: 0.58, blue: 0.82)              // slate blue
    static let mint = Color(red: 0.25, green: 0.68, blue: 0.55)             // sage green
    static let rose = Color(red: 0.78, green: 0.35, blue: 0.48)             // dusty rose
    static let amber = Color(red: 0.85, green: 0.65, blue: 0.25)            // warm amber
    static let periwinkle = Color(red: 0.49, green: 0.55, blue: 1.00)       // Memo chart periwinkle
    static let electricViolet = Color(red: 0.65, green: 0.42, blue: 1.00)   // Memo chart violet

    // Focus unlock slot picker
    static let focusSlotBackground = Color(red: 0.0, green: 0.0, blue: 0.0)       // #000000
    static let focusSlotSurface = Color(red: 0.078, green: 0.078, blue: 0.102)    // #14141A
    static let focusSlotReelSurface = Color(red: 0.063, green: 0.063, blue: 0.086) // #101016
    static let focusSlotTileSurface = Color(red: 0.118, green: 0.118, blue: 0.165) // #1E1E2A
    static let focusSlotSuccess = mint                                       // #40AD8C

    // Reaction time phase colors
    static let reactionWait = Color(red: 0.8, green: 0.15, blue: 0.15)
    static let reactionGo = Color(red: 0.15, green: 0.75, blue: 0.3)
    static let reactionTooEarly = Color(red: 0.85, green: 0.55, blue: 0.1)

    // Gradients — subtle warm gradient for premium feel
    static let accentGradient = LinearGradient(
        colors: [accent, Color(red: 0.35, green: 0.55, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let premiumGradient = LinearGradient(
        colors: [accent, Color(red: 0.22, green: 0.42, blue: 0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = accentGradient
    static let coolGradient = accentGradient

    static let neuralGradient = LinearGradient(
        colors: [accent, accent.opacity(0.7)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Main Screen Titles

struct MainScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .mainScreenTitleStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Text {
    func mainScreenTitleStyle(
        size: CGFloat = 38,
        lineLimit: Int = 1,
        minimumScaleFactor: CGFloat = 0.82
    ) -> some View {
        self
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
@MainActor
struct MainScreenPreview<Content: View>: View {
    private let content: Content
    private let modelContainer: ModelContainer

    @State private var storeService = StoreService(loadProductsOnInit: false)
    @State private var paywallTrigger = PaywallTriggerService()
    @State private var trainingManager = TrainingSessionManager()
    @State private var gameCenterService = GameCenterService()
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var focusModeService = FocusModeService()

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.modelContainer = Self.makeModelContainer()
    }

    var body: some View {
        content
            .environment(storeService)
            .environment(paywallTrigger)
            .environment(trainingManager)
            .environment(gameCenterService)
            .environment(deepLinkRouter)
            .environment(focusModeService)
            .modelContainer(modelContainer)
            .preferredColorScheme(.dark)
    }

    private static func makeModelContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: User.self, Exercise.self, SpacedRepetitionCard.self,
            DailySession.self, BrainScoreResult.self, Achievement.self,
            configurations: configuration
        )
        seed(container.mainContext)
        return container
    }

    private static func seed(_ context: ModelContext) {
        let user = User()
        user.hasCompletedOnboarding = true
        user.username = "Dylan"
        user.level = 6
        user.totalXP = 840
        user.currentStreak = 5
        user.longestStreak = 12
        user.totalExercises = 38
        user.lastSessionDate = .now
        context.insert(user)

        let exerciseTypes: [ExerciseType] = [.reactionTime, .visualMemory, .mathSpeed, .dualNBack]
        for (index, type) in exerciseTypes.enumerated() {
            let exercise = Exercise(
                type: type,
                difficulty: 2 + index,
                score: 0.72 + Double(index) * 0.06,
                durationSeconds: 80 + index * 22
            )
            exercise.completedAt = Calendar.current.date(byAdding: .day, value: -index, to: .now) ?? .now
            context.insert(exercise)
        }

        for dayOffset in 0..<7 {
            let session = DailySession()
            session.date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: .now) ?? .now
            session.totalScore = 0.70 + Double(dayOffset % 3) * 0.07
            session.durationSeconds = 540 + dayOffset * 65
            context.insert(session)
        }

        let brainScore = BrainScoreResult()
        brainScore.brainScore = 742
        brainScore.brainAge = 22
        brainScore.percentile = 86
        brainScore.digitSpanScore = 78
        brainScore.reactionTimeScore = 84
        brainScore.visualMemoryScore = 73
        brainScore.digitSpanMax = 8
        brainScore.reactionTimeAvgMs = 221
        brainScore.visualMemoryMax = 6
        context.insert(brainScore)

    }
}
#endif

// MARK: - App Card Modifier (white card, subtle shadow, 14pt radius)

struct AppCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.cardSurface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: colorScheme == .dark ? 4 : 8, y: 2)
            }
    }
}

extension View {
    func appCard(padding: CGFloat = 16) -> some View {
        modifier(AppCardModifier(padding: padding))
    }

    func pageBackground() -> some View {
        self.background(AppColors.pageBg.ignoresSafeArea())
    }

    func glowingCard(color: Color, intensity: Double = 0.15) -> some View {
        modifier(GlowingCardModifier(color: color, intensity: intensity))
    }

    func heroCard(color: Color) -> some View {
        modifier(HeroCardModifier(color: color))
    }

    /// Constrains content to a readable max width on iPad while staying full-width on iPhone.
    func responsiveContent(maxWidth: CGFloat = 680) -> some View {
        self.frame(maxWidth: maxWidth)
    }
}

struct GlowingCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.cardSurface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: colorScheme == .dark ? 4 : 8, y: 2)
            }
    }
}

struct HeroCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.cardSurface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: colorScheme == .dark ? 4 : 12, y: 4)
            }
    }
}

// MARK: - Accent Button Style (rounded, slight depth/press effect)

struct AccentButtonStyle: ViewModifier {
    var color: Color = AppColors.accent

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .foregroundStyle(.white)
    }
}

extension View {
    func accentButton(color: Color = AppColors.accent) -> some View {
        modifier(AccentButtonStyle(color: color))
    }
}

// MARK: - Gradient Accent Button

struct GradientButtonStyle: ViewModifier {
    var gradient: LinearGradient = AppColors.accentGradient

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .foregroundStyle(.white)
    }
}

extension View {
    func gradientButton(_ gradient: LinearGradient = AppColors.accentGradient) -> some View {
        modifier(GradientButtonStyle(gradient: gradient))
    }
}

// MARK: - Pulsing Button (breathing idle animation for Start buttons)

struct PulsingButton: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.03 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulsingWhenIdle() -> some View {
        modifier(PulsingButton())
    }
}

// MARK: - Section Header (clean, subtle)

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Colored Icon Badge

struct ColoredIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.22))
    }
}

// MARK: - Cognitive Domain

enum CognitiveDomain: String, CaseIterable, Identifiable {
    case memory, speed, attention, flexibility, problemSolving

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .memory: return "Memory"
        case .speed: return "Speed"
        case .attention: return "Attention"
        case .flexibility: return "Flexibility"
        case .problemSolving: return "Problem Solving"
        }
    }

    var color: Color {
        switch self {
        case .memory: return AppColors.violet
        case .speed: return AppColors.coral
        case .attention: return AppColors.sky
        case .flexibility: return AppColors.teal
        case .problemSolving: return AppColors.amber
        }
    }

    var icon: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .speed: return "bolt.fill"
        case .attention: return "eye.fill"
        case .flexibility: return "arrow.triangle.branch"
        case .problemSolving: return "puzzlepiece.fill"
        }
    }
}

// MARK: - Streak Week Calendar

struct StreakWeekView: View {
    let sessions: [Date]
    let currentStreak: Int

    private var weekDays: [(String, Date, Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0) })

        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let dayStr = date.formatted(.dateTime.weekday(.narrow))
            let completed = sessionDays.contains(date)
            return (dayStr, date, completed)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.1) { day, date, completed in
                VStack(spacing: 6) {
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)

                    ZStack {
                        Circle()
                            .fill(completed ? AppColors.accent : AppColors.cardBorder.opacity(0.5))
                            .frame(width: 30, height: 30)

                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        if Calendar.current.isDateInToday(date) && !completed {
                            Circle()
                                .stroke(AppColors.accent, lineWidth: 2)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Staggered Animation Modifier

struct StaggeredEntrance: ViewModifier {
    let index: Int
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(index: Int, delay: Double = 0.025) {
        self.index = index
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0.92)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .onAppear {
                guard !appeared else { return }
                guard !reduceMotion else {
                    appeared = true
                    return
                }
                let boundedDelay = min(Double(index) * delay, 0.06)
                withAnimation(.easeOut(duration: 0.18).delay(boundedDelay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredEntrance(index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }

    func staggered(index: Int, delay: Double = 0.06) -> some View {
        modifier(StaggeredEntrance(index: index, delay: delay))
    }
}

// MARK: - Cognitive Domain Bar

struct CognitiveDomainBar: View {
    let label: String
    let value: Double // 0-100
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(color)

            ProgressView(value: value, total: 100)
                .tint(color)
                .scaleEffect(y: 0.8)

            Text("\(Int(value))%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Streak Ring

struct StreakRingView: View {
    let current: Int
    let goal: Int
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(CGFloat(current) / CGFloat(goal), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.cardBorder, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppColors.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

            VStack(spacing: 2) {
                Text("\(current)")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                Text(current == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Press Button Style (scale on tap)

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Shimmer Modifier (for skeleton loading)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Edge Glow (gameplay state feedback)

struct EdgeGlow: ViewModifier {
    let color: Color
    let intensity: Double // 0.0 to 1.0
    let edge: Edge

    func body(content: Content) -> some View {
        content.overlay(alignment: edge == .top ? .top : .bottom) {
            LinearGradient(
                colors: [color.opacity(0.15 * intensity), .clear],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
            .frame(height: 60)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.5), value: intensity)
        }
    }
}

extension View {
    func edgeGlow(color: Color, intensity: Double, edge: Edge = .top) -> some View {
        modifier(EdgeGlow(color: color, intensity: intensity, edge: edge))
    }
}

// MARK: - Shake Effect (for wrong answers)

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakesPerUnit), y: 0))
    }
}

// MARK: - Brand Font (Bricolage Grotesque)
//
// Bundled in Resources/Fonts. Use `.brand(size:weight:)` instead of
// `.system(size:weight:design:.rounded)` for headlines and UI text.
// Numerals should still use `.monospaced` design (system) for the
// JetBrains-Mono-ish numeric look on count-ups and stats.

extension Font {
    /// Memo brand font (Bricolage Grotesque).
    /// Weights map: regular/medium/semibold/bold/heavy → Regular/Medium/SemiBold/Bold/ExtraBold.
    /// `.black` and any unsupported weight fall back to ExtraBold.
    static func brand(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let postScriptName: String
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            postScriptName = "BricolageGrotesque-Regular"
        case .medium:
            postScriptName = "BricolageGrotesque-Medium"
        case .semibold:
            postScriptName = "BricolageGrotesque-SemiBold"
        case .bold:
            postScriptName = "BricolageGrotesque-Bold"
        case .heavy, .black:
            postScriptName = "BricolageGrotesque-ExtraBold"
        default:
            postScriptName = "BricolageGrotesque-Regular"
        }
        return .custom(postScriptName, size: size)
    }
}

extension Color {
    /// Linearly interpolates between this color and another by `t` ∈ [0, 1].
    /// Routes through UIColor to extract RGBA components since SwiftUI's
    /// Color doesn't expose them directly. Used by the plan reveal page to
    /// blend coral → coralDeep as the projected number climbs.
    func interpolated(with other: Color, by t: Double) -> Color {
        let clamped = CGFloat(max(0.0, min(1.0, t)))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * clamped),
            green: Double(g1 + (g2 - g1) * clamped),
            blue: Double(b1 + (b2 - b1) * clamped),
            opacity: Double(a1 + (a2 - a1) * clamped)
        )
    }
}
