//
//  TotalActivityView.swift
//  FocusUnlocksReport
//
//  Renders the user's pickup count in Memori's Monkeytype-style typography.
//  The main app embeds this via DeviceActivityReport(context: .unlocks).
//

import SwiftUI
import FamilyControls
import ManagedSettings
import UIKit

struct TotalActivityView: View {
    /// Pickup / unlock count produced by TotalActivityReport.
    let totalActivity: Int

    // Design tokens (inline — extension can't import app modules)
    private let fg = Color.white.opacity(0.92)
    private let accent = Color(red: 0.408, green: 0.565, blue: 0.996) // #6890FE

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(totalActivity)")
                .font(.system(size: 140, weight: .bold, design: .monospaced))
                .kerning(-7)
                .foregroundStyle(fg)
                .shadow(color: accent.opacity(0.25), radius: 30)
            Text("×")
                .font(.system(size: 140, weight: .bold, design: .monospaced))
                .kerning(-7)
                .foregroundStyle(accent)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Screen-time stat for the home Idle card. Renders as `4.3 HRS` style.
struct ScreenTimeView: View {
    /// Yesterday's total screen-time duration in hours.
    let hours: Double

    private let coral = Color(red: 0.85, green: 0.40, blue: 0.35)
    private let accent = Color(red: 0.29, green: 0.50, blue: 0.90)
    private let fg = Color.white.opacity(0.92)
    private let fg2 = Color.white.opacity(0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", hours))
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(coral)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .shadow(color: coral.opacity(0.28), radius: 18, y: 8)

                Text("h")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(fg2)
            }

            Text("yesterday's Screen Time")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(fg2)

            Text("real Screen Time data")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Memo-flavored weekly Screen Time bars. The report filter provides the
/// 7-day window ending yesterday, so the rightmost bar is always yesterday.
struct WeeklyScreenTimeChartView: View {
    let hoursByDay: [Double]

    private let surface = Color(red: 0.039, green: 0.039, blue: 0.059)
    private let border = Color.white.opacity(0.10)
    private let grid = Color.white.opacity(0.08)
    private let fg2 = Color.white.opacity(0.58)
    private let mint = Color(red: 0.25, green: 0.68, blue: 0.55)
    private let periwinkle = Color(red: 0.49, green: 0.55, blue: 1.00)
    private let violet = Color(red: 0.65, green: 0.42, blue: 1.00)
    private let coral = Color(red: 0.85, green: 0.40, blue: 0.35)

    private var values: [Double] {
        let padded = Array(hoursByDay.prefix(7)) + Array(repeating: 0, count: max(0, 7 - hoursByDay.count))
        return Array(padded.prefix(7))
    }

    private var labels: [String] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let symbols = calendar.shortWeekdaySymbols

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: windowStart) ?? windowStart
            let weekday = calendar.component(.weekday, from: day) - 1
            let symbol = symbols[max(0, min(weekday, symbols.count - 1))]
            return offset == 6 ? symbol : String(symbol.prefix(1))
        }
    }

    private var axisMax: Double {
        let maxHours = max(values.max() ?? 1, 1)
        return max(2, (ceil((maxHours * 1.10) / 2) * 2))
    }

    private var average: Double {
        let activeValues = values.filter { $0 > 0 }
        guard !activeValues.isEmpty else { return 0 }
        return activeValues.reduce(0, +) / Double(activeValues.count)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let plotLeft: CGFloat = 30
            let plotRight: CGFloat = 30
            let plotTop: CGFloat = 16
            let plotBottom: CGFloat = 24
            let plotWidth = max(1, width - plotLeft - plotRight)
            let plotHeight = max(1, height - plotTop - plotBottom)
            let averageY = plotTop + plotHeight * (1 - min(max(average / axisMax, 0), 1))

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [surface.opacity(0.70), Color.white.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )

                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { index in
                        Rectangle()
                            .fill(grid.opacity(index == 0 ? 0 : 1))
                            .frame(width: index == 0 ? 0 : 1)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.leading, 34)
                .padding(.trailing, 12)
                .padding(.vertical, 10)

                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text(axisLabel(for: index))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(fg2)
                                .frame(width: 26, alignment: .leading)
                            Rectangle()
                                .fill(grid)
                                .frame(height: 1)
                        }
                        if index < 2 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                if average > 0 {
                    Path { path in
                        path.move(to: CGPoint(x: plotLeft, y: averageY))
                        path.addLine(to: CGPoint(x: width - plotRight + 8, y: averageY))
                    }
                    .stroke(
                        mint.opacity(0.72),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 6])
                    )

                    Text("avg")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(mint.opacity(0.88))
                        .position(x: width - 14, y: averageY)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let barHeight = max(value > 0 ? 6 : 2, plotHeight * min(value / axisMax, 1))
                        let isYesterday = index == 6

                        VStack(spacing: 5) {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [violet.opacity(0.98), periwinkle.opacity(0.96)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 18, height: barHeight)
                                    .opacity(value > 0 ? 1 : 0.22)
                                    .shadow(color: violet.opacity(isYesterday ? 0.55 : 0.25), radius: isYesterday ? 12 : 7, y: 4)

                                if isYesterday && value > 0 {
                                    Capsule()
                                        .fill(coral.opacity(0.95))
                                        .frame(width: 18, height: 5)
                                        .shadow(color: coral.opacity(0.55), radius: 8, y: 2)
                                }
                            }

                            Text(labels[index])
                                .font(.system(size: isYesterday ? 10 : 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(isYesterday ? coral.opacity(0.95) : fg2.opacity(0.82))
                                .frame(height: 12)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(width: plotWidth / CGFloat(values.count), height: plotHeight + 17, alignment: .bottom)
                    }
                }
                .frame(width: plotWidth, height: plotHeight + 17, alignment: .bottom)
                .position(x: plotLeft + plotWidth / 2, y: plotTop + (plotHeight + 17) / 2)
            }
        }
    }

    private func axisLabel(for index: Int) -> String {
        switch index {
        case 0: return "\(Int(axisMax.rounded()))h"
        case 1: return "\(Int((axisMax / 2).rounded()))h"
        default: return "0"
        }
    }
}

struct OnboardingWeeklyScreenTimeView: View {
    let configuration: OnboardingWeeklyScreenTimeConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTotalHours: Double = 0

    private let coral = Color(red: 0.98, green: 0.34, blue: 0.29)
    private let accent = Color(red: 0.41, green: 0.56, blue: 1.0)
    private let fg = Color.white.opacity(0.94)
    private let fg2 = Color.white.opacity(0.70)

    private var totalText: String {
        if displayedTotalHours >= 100 {
            return "\(Int(displayedTotalHours.rounded()))"
        }
        return String(format: "%.1f", displayedTotalHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(totalText)
                    .font(.system(size: 124, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(coral)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Text("h")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(fg2)
            }

            Text("hours on your phone this week")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(fg)

            Text("Memo can fix this before the feed opens.")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // The report renders in an opaque out-of-process surface — the app
        // cannot composite behind it, so this must be pixel-identical to the
        // onboarding background (OB.bg in the main app) or the surface reads
        // as a box.
        .background(Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(String(format: "%.1f", configuration.totalHours)) hours of Screen Time in the last 7 days")
        .onAppear {
            startCountUp()
        }
        .onChange(of: configuration.totalHours) { _, _ in
            startCountUp()
        }
    }

    private func startCountUp() {
        guard configuration.totalHours > 0 else {
            displayedTotalHours = 0
            return
        }

        guard !reduceMotion else {
            displayedTotalHours = configuration.totalHours
            impact(style: .medium)
            return
        }

        displayedTotalHours = 0
        Task { @MainActor in
            let steps = 28
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 3)
                displayedTotalHours = configuration.totalHours * eased
                if step % 4 == 0 || step == steps {
                    impact(style: step == steps ? .medium : .light)
                }
                try? await Task.sleep(for: .milliseconds(28))
            }
            displayedTotalHours = configuration.totalHours
        }
    }

    private func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

struct FocusHomeDashboardView: View {
    let configuration: FocusHomeDashboardConfiguration

    private let fg = Color.white.opacity(0.94)
    private let fg2 = Color.white.opacity(0.58)
    private let border = Color.white.opacity(0.10)
    private let coral = Color(red: 0.980, green: 0.420, blue: 0.349)
    private let accent = Color(red: 0.408, green: 0.565, blue: 0.996)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Screen Time Today")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(formatDuration(configuration.totalSeconds))
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(coral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)


                Rectangle()
                    .fill(border)
                    .frame(width: 1, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Phone pickups")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("\(configuration.pickups)")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(border)
                .frame(height: 1)

            Text("Top offenders")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(fg)

            VStack(spacing: 9) {
                if configuration.offenders.isEmpty {
                    Text("No app usage today")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(configuration.offenders) { offender in
                        HStack(spacing: 12) {
                            homeOffenderIcon(offender.icon)

                            Text(offender.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(fg)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Spacer(minLength: 0)

                            Text(formatDuration(offender.seconds))
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(fg)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func homeOffenderIcon(_ icon: FocusInsightsOffenderIcon) -> some View {
        switch icon {
        case .application(let token):
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .category(let token):
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .webDomain(let token):
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .fallback:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(accent)
                )
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}

private struct FocusMascotPNG: View {
    let name: String

    var body: some View {
        if let image = UIImage(contentsOfFile: imagePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(red: 0.49, green: 0.55, blue: 1.00))
        }
    }

    private var imagePath: String {
        Bundle.main.path(forResource: name, ofType: "png") ?? ""
    }
}

#Preview("Unlocks") {
    TotalActivityView(totalActivity: 287)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}

#Preview("Screen Time") {
    ScreenTimeView(hours: 4.3)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
}

#Preview("Weekly Screen Time") {
    WeeklyScreenTimeChartView(hoursByDay: [6.2, 7.8, 5.1, 9.4, 4.2, 8.1, 11.9])
        .preferredColorScheme(.dark)
        .frame(height: 106)
        .padding()
        .background(Color.black)
}
