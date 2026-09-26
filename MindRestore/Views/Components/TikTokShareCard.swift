import SwiftUI

// MARK: - Brain Type Color Helper

private func brainTypeSwiftColor(_ type: BrainType) -> Color {
    switch type {
    case .lightningReflex: return AppColors.coral
    case .numberCruncher: return AppColors.indigo
    case .patternMaster: return AppColors.violet
    case .balancedBrain: return AppColors.mint
    }
}

// MARK: - Shared Components (Warm Light Design)

/// Adaptive background — warm cream in light mode, deep purple-black in dark mode
private struct CardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.14),
                    Color(red: 0.12, green: 0.08, blue: 0.20),
                    Color(red: 0.08, green: 0.06, blue: 0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.969, green: 0.961, blue: 0.941),
                    Color(red: 0.955, green: 0.945, blue: 0.925),
                    Color(red: 0.969, green: 0.961, blue: 0.941)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct BrandingHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.accent)
            Text("MEMO")
                .font(.system(size: 12, weight: .heavy))
                .tracking(3)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.6) : Color(red: 0.45, green: 0.43, blue: 0.40))
        }
    }
}

private struct BrandingFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Test yours free \u{2014} Memo")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.4) : Color(red: 0.62, green: 0.60, blue: 0.58))
    }
}

/// Pill badge with soft colored background
private struct RatingPill<Content: View>: View {
    let color: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Score Bar (Light)

private struct ScoreBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    private var fraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return min(CGFloat(value / maxValue), 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.12))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 14)

            Text(String(format: "%.0f", value))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// Inner card surface — white on cream in light, subtle dark surface in dark mode
private struct ShareCardSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 12, y: 4)
            )
    }
}

// MARK: - 1. BrainScoreShareCard


// MARK: - 4. ReactionTimeShareCard

struct ReactionTimeShareCard: View {
    let averageMs: Int
    let bestMs: Int
    let ratingText: String
    let roundTimes: [Int]

    private var ratingColor: Color {
        if averageMs < 200 { return Color.green }
        if averageMs < 250 { return AppColors.accent }
        if averageMs < 300 { return AppColors.sky }
        if averageMs < 350 { return AppColors.amber }
        return AppColors.coral
    }

    var body: some View {
        ZStack {
            CardBackground()

            VStack(spacing: 0) {
                Spacer().frame(height: 32)
                BrandingHeader()
                Spacer().frame(height: 28)

                ShareCardSurface {
                    VStack(spacing: 16) {
                        // Exercise header
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("REACTION TIME")
                                .font(.system(size: 13, weight: .heavy))
                                .tracking(3)
                        }
                        .foregroundStyle(AppColors.coral)

                        // Big average
                        Text("\(averageMs)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(ratingColor)

                        Text("MILLISECONDS")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(4)
                            .foregroundStyle(.secondary)

                        // Rating
                        RatingPill(color: ratingColor) {
                            Text(ratingText.uppercased())
                        }

                        Divider()

                        // Round breakdown
                        HStack(spacing: 0) {
                            ForEach(Array(roundTimes.enumerated()), id: \.offset) { index, ms in
                                VStack(spacing: 4) {
                                    Text("R\(index + 1)")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(.secondary)
                                    Text("\(ms)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(ms == bestMs ? ratingColor : .primary.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        // Best
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColors.amber)
                            Text("Best: \(bestMs)ms")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("Think you're faster?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer().frame(height: 10)
                BrandingFooter()
                Spacer().frame(height: 28)
            }
        }
        .frame(width: 360, height: 640)
    }
}

// MARK: - 5. Generic ExerciseShareCard (Premium Redesign)

struct ExerciseShareCard: View {
    let exerciseName: String
    let exerciseIcon: String
    let accentColor: Color
    let mainValue: String
    let mainLabel: String
    let ratingText: String
    let stats: [(label: String, value: String)]
    let ctaText: String

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    // Slightly desaturated accent for backgrounds
    private var glowColor: Color { accentColor.opacity(isDark ? 0.35 : 0.18) }

    var body: some View {
        ZStack {
            exerciseCardBackground

            VStack(spacing: 0) {
                Spacer().frame(height: 36)
                exerciseCardBrandingHeader
                Spacer().frame(height: 32)
                exerciseIdentity
                Spacer().frame(height: 28)
                exerciseHeroScore
                Spacer().frame(height: 16)
                exerciseRatingPill
                Spacer().frame(height: 28)
                exerciseStatsRow
                Spacer()
                exerciseCTA
                Spacer().frame(height: 16)
                exerciseCardBrandingFooter
                Spacer().frame(height: 28)
            }
        }
        .frame(width: 360, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var cardPrimaryText: Color {
        isDark ? .white : Color(red: 0.12, green: 0.12, blue: 0.15)
    }

    private var cardSecondaryText: Color {
        isDark ? Color.white.opacity(0.40) : Color(red: 0.50, green: 0.48, blue: 0.46)
    }

    private var exerciseIdentity: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(isDark ? 0.18 : 0.12))
                    .frame(width: 56, height: 56)
                Circle()
                    .stroke(accentColor.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Image(systemName: exerciseIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(exerciseName.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(accentColor)
        }
    }

    private var exerciseHeroScore: some View {
        ZStack {
            Circle()
                .fill(heroGlow)
                .frame(width: 240, height: 240)

            VStack(spacing: 4) {
                Text(mainValue)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(cardPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                Text(mainLabel.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(cardSecondaryText)
            }
        }
        .frame(height: 140)
    }

    private var heroGlow: RadialGradient {
        RadialGradient(
            colors: [
                accentColor.opacity(isDark ? 0.30 : 0.15),
                accentColor.opacity(isDark ? 0.08 : 0.03),
                .clear
            ],
            center: .center,
            startRadius: 20,
            endRadius: 120
        )
    }

    private var exerciseRatingPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
            Text(ratingText.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Capsule().fill(accentColor.opacity(isDark ? 0.15 : 0.10)))
        .overlay(Capsule().stroke(accentColor.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private var exerciseStatsRow: some View {
        if !stats.isEmpty {
            HStack(spacing: 0) {
                ForEach(stats.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            .frame(width: 1, height: 32)
                    }
                    exerciseStat(stats[index])
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
            )
            .padding(.horizontal, 24)
        }
    }

    private func exerciseStat(_ stat: (label: String, value: String)) -> some View {
        VStack(spacing: 3) {
            Text(stat.value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(cardPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(cardSecondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var exerciseCTA: some View {
        Text(ctaText)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 13)
            .background(Capsule().fill(accentColor))
            .shadow(color: accentColor.opacity(0.4), radius: 12, y: 4)
    }

    // MARK: - Sub-views

    private var exerciseCardBackground: some View {
        ZStack {
            // Base gradient
            if isDark {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.08),
                        Color(red: 0.07, green: 0.06, blue: 0.12),
                        Color(red: 0.04, green: 0.04, blue: 0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.98, blue: 0.99),
                        Color(red: 0.96, green: 0.96, blue: 0.97),
                        Color(red: 0.98, green: 0.98, blue: 0.99)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // Accent color radial glow (upper-center bloom)
            RadialGradient(
                colors: [
                    accentColor.opacity(isDark ? 0.12 : 0.06),
                    accentColor.opacity(isDark ? 0.04 : 0.02),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 40,
                endRadius: 260
            )

            // Subtle noise/texture via thin border lines
            VStack {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    .frame(height: 0.5)
                Spacer()
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    .frame(height: 0.5)
            }
        }
    }

    private var exerciseCardBrandingHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accentColor)
            Text("MEMO")
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(isDark ? Color.white.opacity(0.50) : Color(red: 0.40, green: 0.38, blue: 0.36))
        }
    }

    private var exerciseCardBrandingFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("Free on the App Store")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isDark ? Color.white.opacity(0.30) : Color(red: 0.58, green: 0.56, blue: 0.54))
    }
}

// MARK: - Previews

#Preview("Exercise Card — Dark") {
    ExerciseShareCard(
        exerciseName: "Color Match",
        exerciseIcon: "paintpalette.fill",
        accentColor: AppColors.violet,
        mainValue: "95%",
        mainLabel: "Accuracy",
        ratingText: "Stroop Master",
        stats: [
            ("Correct", "19/20"),
            ("Avg Time", "842ms"),
            ("Score", "92%")
        ],
        ctaText: "Can you beat this?"
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Exercise Card — Light") {
    ExerciseShareCard(
        exerciseName: "Dual N-Back",
        exerciseIcon: "square.grid.3x3.fill",
        accentColor: AppColors.accent,
        mainValue: "87%",
        mainLabel: "Accuracy",
        ratingText: "Elite Focus",
        stats: [
            ("Level", "N-3"),
            ("Rounds", "20"),
            ("Best", "92%")
        ],
        ctaText: "Can you beat this?"
    )
    .environment(\.colorScheme, .light)
}

// MARK: - Render to Image

extension View {
    @MainActor
    func renderAsImage(size: CGSize = CGSize(width: 300, height: 400), scale: CGFloat? = nil) -> UIImage {
        // Detect current color scheme and pass it to the renderer
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        let content = self.environment(\.colorScheme, isDark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = .init(size)
        renderer.scale = scale ?? UIScreen.main.scale
        return renderer.uiImage ?? UIImage()
    }
}
