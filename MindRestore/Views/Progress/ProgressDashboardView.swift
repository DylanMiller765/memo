import SwiftUI
import SwiftData
import Charts
import FamilyControls
import DeviceActivity

// MARK: - Time Range

private enum TimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}

#if DEBUG
#Preview("Insights") {
    MainScreenPreview {
        ProgressDashboardView()
    }
}
#endif

private enum InsightsMode: String, CaseIterable {
    case focus = "Focus"
    case brain = "Brain"

    var accentColor: Color {
        switch self {
        case .focus: return AppColors.mint
        case .brain: return AppColors.accent
        }
    }
}

private struct FocusReportDay: Identifiable {
    let id = UUID()
    let date: Date
    let hours: Double

    var dayLabel: String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    var dateLabel: String {
        date.formatted(.dateTime.day())
    }
}

private struct FocusOffender: Identifiable {
    let id = UUID()
    let name: String
    let seconds: TimeInterval
}

// MARK: - Insights Dashboard

struct ProgressDashboardView: View {
    @Environment(StoreService.self) private var storeService
    @Environment(FocusModeService.self) private var focusModeService
    @Query private var users: [User]
    @Query(sort: \DailySession.date, order: .reverse) private var sessions: [DailySession]
    @Query(sort: \BrainScoreResult.date, order: .reverse) private var brainScores: [BrainScoreResult]
    @Query private var achievements: [Achievement]
    @Query(sort: \Exercise.completedAt, order: .reverse) private var exercises: [Exercise]

    @State private var selectedRange: TimeRange = .week
    @State private var selectedMode: InsightsMode = .focus
    @State private var showingPaywall = false

    private var user: User? { users.first }
    private var isProUser: Bool { storeService.isProUser }
    private var hasBrainInsightData: Bool { !sessions.isEmpty || !brainScores.isEmpty }
    private var hasFocusInsightData: Bool {
        screenshotMode
            || focusDemoDataEnabled
            || focusModeService.isEnabled
            || focusModeService.blockedAppCount > 0
            || focusModeService.dailyAttemptCount > 0
            || focusModeService.weeklyBlockedMinutes > 0
            || focusModeService.authorizationStatus == .approved
    }
    private var hasAnyInsightData: Bool { hasFocusInsightData }

    // MARK: - Filtered Data

    private var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
    }

    private var filteredScores: [BrainScoreResult] {
        brainScores.filter { $0.date >= cutoffDate }
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { $0.completedAt >= cutoffDate }
    }

    /// Current (latest) brain score
    private var currentScore: BrainScoreResult? {
        brainScores.first
    }

    /// Brain score at the start of the selected period (or earliest in range)
    private var periodStartScore: BrainScoreResult? {
        filteredScores.last
    }

    /// Delta: current brain score minus score at start of period
    private var scoreDelta: Int {
        guard let current = currentScore, let start = periodStartScore,
              current.id != start.id else { return 0 }
        return current.brainScore - start.brainScore
    }

    /// Delta for brain age (lower is better)
    private var brainAgeDelta: Int {
        guard let current = currentScore, let start = periodStartScore,
              current.id != start.id else { return 0 }
        return current.brainAge - start.brainAge
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                if !hasAnyInsightData {
                    emptyState
                } else {
                    insightsContent()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 120)
                        .responsiveContent()
                        .frame(maxWidth: .infinity)
                }
            }
            .pageBackground()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private func insightsContent() -> some View {
        VStack(spacing: 20) {
            insightsHeader
                .staggeredEntrance(index: 0)
            focusInsightsTab()
                .staggeredEntrance(index: 1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 40)

            Image("mascot-bored")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 160)

            Text("No Progress Yet")
                .font(.title3.weight(.semibold))

            Text("Complete your first exercise to see your progress here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCard()
        .padding(.horizontal)
        .padding(.top, 8)
        .staggeredEntrance(index: 0)
    }

    // MARK: - Mode Picker

    private var insightsHeader: some View {
        MainScreenTitle(text: "Insights")
    }


    // MARK: - Focus Tab

    @ViewBuilder
    private func focusInsightsTab() -> some View {
        #if DEBUG
        if screenshotMode {
            focusScreenshotInsightsTab
        } else {
            focusPermissionBackedInsightsTab
        }
        #else
        focusPermissionBackedInsightsTab
        #endif
    }

    private var focusPermissionBackedInsightsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch focusModeService.authorizationStatus {
            case .approved:
                DeviceActivityReport(.focusInsightsInteractive, filter: focusInsightsDeviceActivityFilter)
                    .frame(height: 900, alignment: .topLeading)
            case .notDetermined:
                focusScreenTimePermissionCard(
                    title: "Connect Screen Time",
                    subtitle: "Show your real weekly usage, daily breakdowns, and top offenders."
                )
            case .denied:
                focusScreenTimePermissionCard(
                    title: "Screen Time is off",
                    subtitle: "Allow Screen Time access in Settings to show real Insights data."
                )
            @unknown default:
                focusScreenTimePermissionCard(
                    title: "Screen Time unavailable",
                    subtitle: "Memo can show Focus insights after Screen Time access is available."
                )
            }
        }
    }

    #if DEBUG
    private var screenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-mode")
    }

    private var focusScreenshotInsightsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY'S FEED RECEIPT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.coral)
                    .textCase(.uppercase)

                statsRow(label: "Time on distractions", value: "4h 14m", delta: nil, inverted: false)
                thinDivider
                statsRow(label: "Pickups stopped", value: "33", delta: nil, inverted: false)
                thinDivider
                statsRow(label: "Protected this week", value: "10h 14m", delta: nil, inverted: false)
            }
            .appCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("7-DAY TREND")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.accent)
                    .textCase(.uppercase)

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(focusWeekDays.enumerated()), id: \.element.id) { index, day in
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index >= 5 ? AppColors.mint : AppColors.coral.opacity(0.64))
                                .frame(height: max(28, day.hours / 6.5 * 126))

                            Text(day.dayLabel.prefix(1))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 160, alignment: .bottom)
            }
            .appCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("BY AGE 80")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.mint)
                    .textCase(.uppercase)

                Text("This pace costs about 10.6 years.")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Cutting even one hour a day gives years back.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .appCard()
        }
    }
    #else
    private var screenshotMode: Bool { false }
    #endif

    private var focusInsightsDeviceActivityFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: windowStart, end: .now)),
            devices: DeviceActivityFilter.Devices([.iPhone])
        )
    }

    private func focusScreenTimePermissionCard(title: String, subtitle: String) -> some View {
        Button {
            if focusModeService.authorizationStatus == .notDetermined {
                Task { await focusModeService.requestAuthorization() }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 42, height: 42)
                    .background(AppColors.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppColors.cardSurface.opacity(0.64), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.cardBorder.opacity(0.50), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var focusReportHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Screen Time Report")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text(focusRangeSubtitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var focusRangeSubtitle: String {
        switch selectedRange {
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        }
    }

    private var focusMascotWeekStrip: some View {
        let days = focusWeekDays
        let average = focusAverageHours

        return HStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                focusMascotDay(
                    day,
                    isToday: index == days.count - 1,
                    average: average
                )
            }
        }
    }

    private func focusMascotDay(_ day: FocusReportDay, isToday: Bool, average: Double) -> some View {
        let state = focusMascotState(for: day.hours, average: average)
        let background = isToday ? state.color.opacity(0.10) : AppColors.cardSurface.opacity(0.42)
        let border = isToday ? state.color.opacity(0.62) : AppColors.cardBorder.opacity(0.36)

        return VStack(spacing: 5) {
            Text(day.dayLabel)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(isToday ? Color.primary : AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Image(state.assetName)
                .resizable()
                .scaledToFit()
                .frame(height: isToday ? 42 : 38)
            Text(day.dateLabel)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(state.color)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(border, lineWidth: 1))
        .accessibilityLabel("\(day.dayLabel) \(day.dateLabel), \(formatHours(day.hours))")
    }

    private var focusStatsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                focusStatCell(title: "TOTAL", value: formatHours(focusTotalHours), detail: nil)
                verticalRule
                focusStatCell(title: "DAILY AVG", value: formatHours(focusAverageHours), detail: nil)
            }

            thinDivider.padding(.vertical, 12)

            HStack(spacing: 0) {
                focusStatCell(title: "PEAK DAY", value: focusPeakDayLabel, detail: focusPeakDayDetail)
                verticalRule
                focusStatCell(title: "PICKUPS", value: "\(focusPickupCount)", detail: "\(max(0, focusPickupCount / 7))/day")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardSurface.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.cardBorder.opacity(0.54), lineWidth: 1)
        )
    }

    private func focusStatCell(title: String, value: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(AppColors.cardBorder.opacity(0.42))
            .frame(width: 1, height: 46)
    }

    private var focusBarChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Screen Time Per Day")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("avg \(formatHours(focusAverageHours))")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.mint)
                    .monospacedDigit()
            }

            focusBarChart
        }
    }

    private var focusBarChart: some View {
        let days = focusWeekDays
        let maxHours = max(ceil(days.map(\.hours).max() ?? 1), 1)
        let average = focusAverageHours

        return GeometryReader { proxy in
            let height = proxy.size.height
            let plotTop: CGFloat = 18
            let plotBottom: CGFloat = 28
            let plotHeight = max(1, height - plotTop - plotBottom)
            let averageY = plotTop + plotHeight * (1 - min(max(average / maxHours, 0), 1))

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach([1, 0.5, 0], id: \.self) { value in
                        HStack(spacing: 8) {
                            Text(value == 0 ? "0" : "\(Int((maxHours * value).rounded()))h")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.70))
                                .frame(width: 24, alignment: .leading)

                            Rectangle()
                                .fill(AppColors.cardBorder.opacity(value == 0 ? 0.28 : 0.16))
                                .frame(height: 1)
                        }
                        if value != 0 { Spacer(minLength: 0) }
                    }
                }
                .padding(.top, plotTop)
                .padding(.bottom, plotBottom)

                Path { path in
                    path.move(to: CGPoint(x: 30, y: averageY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: averageY))
                }
                .stroke(AppColors.mint.opacity(0.58), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [6, 7]))

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days) { day in
                        VStack(spacing: 7) {
                            Text(formatHours(day.hours))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: barColors(for: day.hours, average: average),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: max(day.hours > 0 ? 10 : 4, CGFloat(day.hours / maxHours) * plotHeight))

                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .padding(.leading, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 210)
    }

    private var focusOffendersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Offenders")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(focusOffenders.prefix(4).enumerated()), id: \.element.id) { index, offender in
                    focusOffenderRow(offender, index: index)

                    if index < min(focusOffenders.count, 4) - 1 {
                        thinDivider
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(AppColors.cardSurface.opacity(0.54), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.cardBorder.opacity(0.46), lineWidth: 1)
            )
        }
    }

    private func focusOffenderRow(_ offender: FocusOffender, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 18)
            focusOffenderIcon(index: index)
            Text(offender.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            Text(formatDuration(offender.seconds))
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func focusOffenderIcon(index: Int) -> some View {
        let tokens = Array(focusModeService.activitySelection.applicationTokens)
        if tokens.indices.contains(index) {
            Label(tokens[index])
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppColors.accent.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(AppColors.accent)
                )
        }
    }

    // MARK: - 1. Brain Score Trendline

    private var trendlineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header label
            Text("BRAIN SCORE \u{00B7} \(selectedRange.rawValue)")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Large score + delta
            if let score = currentScore {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score.brainScore)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    if isProUser, scoreDelta != 0 {
                        deltaLabel(value: scoreDelta, inverted: false)
                    }
                }
            }

            // Chart — Pro gets full chart, free gets blurred teaser
            if isProUser {
                if filteredScores.count >= 2 {
                    trendlineChart
                        .frame(height: 160)
                } else {
                    Text("Not enough data for this period")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            } else {
                // Free user: blurred chart teaser
                chartProTeaser
            }
        }
    }

    private var chartProTeaser: some View {
        ZStack {
            // Show actual chart if data exists, otherwise placeholder bars
            if filteredScores.count >= 2 {
                trendlineChart
                    .frame(height: 160)
                    .blur(radius: 8)
            } else {
                // Placeholder bars for visual effect
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.accent.opacity(0.3))
                            .frame(height: CGFloat([40, 60, 50, 80, 70, 90, 85, 65, 95, 75, 55, 100][i]))
                    }
                }
                .frame(height: 160)
                .blur(radius: 8)
            }

            // Overlay
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

                Text("Unlock detailed insights")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock Memo")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppColors.accent, in: Capsule())
                }
            }
        }
        .frame(height: 160)
    }

    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedRange == range ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selectedRange == range {
                                Capsule()
                                    .fill(AppColors.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppColors.cardSurface, in: Capsule())
    }

    private var trendlineChart: some View {
        let chartData = filteredScores.sorted { $0.date < $1.date }
        let scores = chartData.map(\.brainScore)
        let rawMin = scores.min() ?? 0
        let rawMax = scores.max() ?? 1000
        let span = max(rawMax - rawMin, 1)
        // 50pt minimum padding or 40% of span — keeps line floating instead of hugging edges
        let padding = max(50, span * 2 / 5)
        let minScore = max(0, rawMin - padding)
        let maxScore = min(1000, rawMax + padding)
        let lastIndex = chartData.count - 1

        return Chart {
            ForEach(Array(chartData.enumerated()), id: \.element.id) { index, item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Score", item.brainScore)
                )
                .foregroundStyle(AppColors.accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Score", item.brainScore)
                )
                .foregroundStyle(AppColors.accent)
                .symbolSize(index == lastIndex ? 80 : 24)
            }
        }
        .chartYScale(domain: minScore...maxScore)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.top, 8)
                .padding(.trailing, 8)
                .padding(.bottom, 4)
        }
        .clipped()
    }

    // MARK: - 2. Stats Table

    private var statsTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Column headers
            HStack {
                Text("METRIC")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if isProUser {
                    Text("VALUE \u{00B7} \u{0394}\(selectedRange.rawValue)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                } else {
                    Text("VALUE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            Divider().opacity(0.3)

            // Rows
            VStack(spacing: 0) {
                // Brain Score
                if let score = currentScore {
                    statsRow(
                        label: "Brain Score",
                        value: "\(score.brainScore) / 1000",
                        delta: isProUser ? scoreDelta : nil,
                        inverted: false
                    )
                    thinDivider
                }

                // Brain Age
                if let score = currentScore {
                    statsRow(
                        label: "Brain Age",
                        value: "\(score.brainAge) yrs",
                        delta: isProUser ? brainAgeDelta : nil,
                        inverted: true
                    )
                    thinDivider
                }

                // Best Rank (Pro only)
                if isProUser, let bestRank = bestPersonalRecord {
                    statsRow(
                        label: "Best Rank",
                        value: "\(bestRank.type.displayName) \u{00B7} \(personalBestDisplay(type: bestRank.type, value: bestRank.best))",
                        delta: nil,
                        inverted: false
                    )
                    thinDivider
                }

                // Streak
                if let user = user {
                    statsRow(
                        label: "Streak",
                        value: "\(user.currentStreak) days",
                        delta: nil,
                        inverted: false,
                        suffix: "best \(user.longestStreak)"
                    )
                    thinDivider
                }

                // Games Played
                statsRow(
                    label: "Games Played",
                    value: "\(user?.totalExercises ?? exercises.count)",
                    delta: nil,
                    inverted: false
                )

                // Time Trained (Pro only)
                if isProUser {
                    thinDivider
                    statsRow(
                        label: "Time Trained",
                        value: formatTotalTime(),
                        delta: nil,
                        inverted: false
                    )
                }
            }
        }
    }

    private func statsRow(label: String, value: String, delta: Int? = nil, inverted: Bool, suffix: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let delta = delta, delta != 0 {
                    deltaLabel(value: delta, inverted: inverted)
                }

                if let suffix = suffix {
                    Text(suffix)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var thinDivider: some View {
        Divider().opacity(0.15)
    }

    // MARK: - 3. Cognitive Domains

    private var cognitiveDomainsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COGNITIVE DOMAINS")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let score = currentScore {
                VStack(spacing: 12) {
                    domainBar(label: "Memory", score: score.digitSpanScore, color: AppColors.violet)
                    domainBar(label: "Speed", score: score.reactionTimeScore, color: AppColors.coral)
                    domainBar(label: "Visual", score: score.visualMemoryScore, color: AppColors.sky)
                }
            } else {
                Text("Complete a brain assessment to see your domain scores")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func domainBar(label: String, score: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color.opacity(0.12))

                    RoundedRectangle(cornerRadius: 5)
                        .fill(color)
                        .frame(width: geo.size.width * min(1, score / 100))
                }
            }
            .frame(height: 10)

            Text("\(Int(score))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 28, alignment: .trailing)

            Text("/ 100")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Focus Mode Stats

    private var focusModeStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FOCUS MODE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(AppColors.violet)
                    .textCase(.uppercase)

                Spacer()

                if focusModeService.isEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColors.violet)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.violet)
                    }
                }
            }

            Divider().opacity(0.3)

            VStack(spacing: 0) {
                statsRow(
                    label: "Shield blocks today",
                    value: "\(focusModeService.dailyAttemptCount)",
                    delta: nil,
                    inverted: false
                )
                thinDivider

                statsRow(
                    label: "Apps blocked",
                    value: "\(focusModeService.blockedAppCount)",
                    delta: nil,
                    inverted: false
                )
                thinDivider

                statsRow(
                    label: "Unlock window",
                    value: "5–20 min",
                    delta: nil,
                    inverted: false
                )

                if focusModeService.isTemporarilyUnlocked, let until = focusModeService.unlockUntil {
                    thinDivider
                    let remaining = max(0, Int(until.timeIntervalSince(.now)) / 60)
                    statsRow(
                        label: "Currently unlocked",
                        value: "\(remaining) min left",
                        delta: nil,
                        inverted: false
                    )
                }
            }

            if !focusModeService.isEnabled {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 12))
                        Text("Set up Focus Mode")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.violet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColors.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var focusDefaults: UserDefaults {
        UserDefaults(suiteName: "group.com.memori.shared") ?? .standard
    }

    private var focusDemoDataEnabled: Bool {
        #if DEBUG
        focusDefaults.bool(forKey: "focus_demo_data_enabled")
        #else
        false
        #endif
    }

    private var focusWeekHours: [Double] {
        let stored = focusDefaults.array(forKey: "focus_demo_weekly_screen_time_hours") as? [Double] ?? []
        if focusDemoDataEnabled, !stored.isEmpty {
            return Array((Array(repeating: 0.0, count: max(0, 7 - stored.count)) + stored).suffix(7))
        }

        if focusModeService.weeklyBlockedMinutes > 0 || focusModeService.dailyAttemptCount > 0 {
            let seed = max(Double(focusModeService.weeklyBlockedMinutes) / 60, Double(focusModeService.dailyAttemptCount) * 0.18, 0.55)
            return [0.82, 1.05, 0.96, 1.12, 0.42, 0.68, 0.74].map { min(7.5, max(0.15, seed * $0)) }
        }

        return [0, 0, 0, 0, 0, 0, 0]
    }

    private var focusWeekDays: [FocusReportDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return focusWeekHours.enumerated().map { index, hours in
            let date = calendar.date(byAdding: .day, value: index - 6, to: today) ?? today
            return FocusReportDay(date: date, hours: hours)
        }
    }

    private var focusTotalHours: Double {
        focusWeekHours.reduce(0, +)
    }

    private var focusAverageHours: Double {
        let active = focusWeekHours.filter { $0 > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0, +) / Double(active.count)
    }

    private var focusPeakDay: FocusReportDay? {
        focusWeekDays.max { $0.hours < $1.hours }
    }

    private var focusPeakDayLabel: String {
        guard let peak = focusPeakDay, peak.hours > 0 else { return "--" }
        return peak.date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var focusPeakDayDetail: String? {
        guard let peak = focusPeakDay, peak.hours > 0 else { return nil }
        return formatHours(peak.hours)
    }

    private var focusPickupCount: Int {
        let stored = focusDefaults.integer(forKey: "focus_demo_pickups")
        if focusDemoDataEnabled, stored > 0 { return stored }

        let receiptAttempts = focusDefaults.integer(forKey: "focus_receipt_blocked_attempts")
        if receiptAttempts > 0 { return receiptAttempts }

        let dailyAttempts = focusDefaults.integer(forKey: "focus_daily_attempt_count")
        if dailyAttempts > 0 { return dailyAttempts }

        return focusModeService.dailyAttemptCount
    }

    private var focusOffenders: [FocusOffender] {
        let names = focusDefaults.stringArray(forKey: "focus_demo_offender_names") ?? []
        let seconds = focusDefaults.array(forKey: "focus_demo_offender_seconds") as? [Int] ?? []

        if focusDemoDataEnabled, !names.isEmpty {
            return names.enumerated().map { index, name in
                FocusOffender(
                    name: name,
                    seconds: TimeInterval(seconds.indices.contains(index) ? seconds[index] : 0)
                )
            }
        }

        if focusModeService.blockedAppCount > 0 {
            let totalSeconds = max(focusTotalHours * 3600, Double(focusModeService.weeklyBlockedMinutes * 60))
            return [
                FocusOffender(name: "Locked target", seconds: totalSeconds * 0.46),
                FocusOffender(name: "Feed app", seconds: totalSeconds * 0.31),
                FocusOffender(name: "Scroll loop", seconds: totalSeconds * 0.18)
            ].filter { $0.seconds > 0 }
        }

        return [
            FocusOffender(name: "YouTube", seconds: TimeInterval(97 * 60)),
            FocusOffender(name: "Instagram", seconds: TimeInterval(74 * 60)),
            FocusOffender(name: "TikTok", seconds: TimeInterval(58 * 60))
        ]
    }

    private func focusMascotState(for hours: Double, average: Double) -> (assetName: String, color: Color) {
        guard hours > 0, average > 0 else {
            return ("mascot-thinking", AppColors.textSecondary)
        }

        if hours >= average * 1.10 {
            return ("mascot-locked-sad", AppColors.coral)
        }

        if hours <= average * 0.90 {
            return ("mascot-unlocked", AppColors.mint)
        }

        return ("mascot-thinking", AppColors.periwinkle)
    }

    private func barColors(for hours: Double, average: Double) -> [Color] {
        if average > 0, hours >= average * 1.10 {
            return [AppColors.coral, AppColors.periwinkle, AppColors.accent]
        }

        if average > 0, hours <= average * 0.90, hours > 0 {
            return [AppColors.mint, AppColors.periwinkle, AppColors.accent]
        }

        return [AppColors.periwinkle, AppColors.accent]
    }

    private func formatHours(_ hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let hourPart = totalMinutes / 60
        let minutePart = totalMinutes % 60
        if hourPart == 0 { return "\(minutePart)m" }
        if minutePart == 0 { return "\(hourPart)h" }
        return "\(hourPart)h \(minutePart)m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        formatHours(seconds / 3600)
    }

    // MARK: - Pro Sections Teaser (blurred)

    private var proSectionsTeaser: some View {
        ZStack {
            VStack(spacing: 28) {
                // Show a preview of cognitive domains + personal bests
                cognitiveDomainsSection
                personalBestsSection
            }
            .blur(radius: 6)
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

                Text("Detailed analytics")
                    .font(.system(size: 15, weight: .semibold))

                Text("Personal bests, training activity,\nand cognitive domain breakdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock Memo")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppColors.accent, in: Capsule())
                }
            }
        }
    }

    // MARK: - 4. Personal Bests (Pro only)

    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERSONAL BESTS")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Divider().opacity(0.3)

            let bests = allPersonalBests
            if bests.isEmpty {
                Text("Play some games to see your personal bests")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bests.enumerated()), id: \.offset) { index, record in
                        statsRow(
                            label: record.type.displayName,
                            value: personalBestDisplay(type: record.type, value: record.best),
                            delta: nil,
                            inverted: false
                        )
                        if index < bests.count - 1 {
                            thinDivider
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Training Heatmap (Pro only)

    private var trainingHeatmapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TRAINING ACTIVITY")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let days = heatmapDays
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

            // Day-of-week headers
            HStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                // Leading spacers for alignment to correct day of week
                ForEach(0..<leadingSpacerCount, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }

                ForEach(days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatmapColor(for: day.count))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private struct HeatmapDay {
        let date: Date
        let count: Int
    }

    private var heatmapDays: [HeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build exercise counts per day for last 30 days
        var countsByDay: [Date: Int] = [:]
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        for exercise in exercises {
            let day = calendar.startOfDay(for: exercise.completedAt)
            if day >= thirtyDaysAgo && day <= today {
                countsByDay[day, default: 0] += 1
            }
        }

        // Generate all 30 days
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: thirtyDaysAgo) else { return nil }
            return HeatmapDay(date: date, count: countsByDay[date] ?? 0)
        }
    }

    /// Number of empty cells before the first day to align with correct weekday column (Mon=0)
    private var leadingSpacerCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -29, to: today) else { return 0 }
        // weekday: 1=Sun, 2=Mon, ... 7=Sat -> convert to Mon=0
        let weekday = calendar.component(.weekday, from: firstDay)
        // Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
        return (weekday + 5) % 7
    }

    private func heatmapColor(for count: Int) -> Color {
        if count == 0 {
            return AppColors.cardSurface
        } else if count <= 2 {
            return AppColors.accent.opacity(0.3)
        } else {
            return AppColors.accent
        }
    }

    // MARK: - Helpers

    private func deltaLabel(value: Int, inverted: Bool) -> some View {
        let isPositive = value > 0
        // For inverted metrics (brain age), negative = good
        let isGood = inverted ? !isPositive : isPositive
        let color = isGood
            ? AppColors.mint
            : AppColors.coral
        let prefix = isPositive ? "+" : ""
        let suffix = inverted ? "y" : ""

        return Text("\(prefix)\(value)\(suffix)")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(color)
    }

    private static let availableGames: [ExerciseType] = [
        .reactionTime, .colorMatch, .speedMatch, .visualMemory,
        .sequentialMemory, .mathSpeed, .dualNBack, .chunkingTraining,
        .chimpTest, .verbalMemory
    ]

    private var bestPersonalRecord: (type: ExerciseType, best: Int)? {
        // Find the game with the highest personal best (normalized by checking all)
        let records: [(type: ExerciseType, best: Int)] = Self.availableGames.compactMap { type in
            let best = PersonalBestTracker.shared.best(for: type)
            guard best > 0 else { return nil }
            return (type: type, best: best)
        }
        // Just return the first non-zero record (most recently set tends to be top)
        return records.first
    }

    /// All personal bests for games the user has played (score > 0)
    private var allPersonalBests: [(type: ExerciseType, best: Int)] {
        Self.availableGames.compactMap { type in
            let best = PersonalBestTracker.shared.best(for: type)
            guard best > 0 else { return nil }
            return (type: type, best: best)
        }
    }

    private func personalBestDisplay(type: ExerciseType, value: Int) -> String {
        switch type {
        case .reactionTime: return "\(1000 - value)ms"
        case .dualNBack: return "N=\(value)"
        case .sequentialMemory: return "\(value) digits"
        case .visualMemory: return "Level \(value)"
        case .mathSpeed: return "\(value) solved"
        case .colorMatch, .speedMatch: return "\(value)%"
        case .chunkingTraining: return "\(value)"
        case .chimpTest: return "Level \(value)"
        case .verbalMemory: return "\(value) words"
        case .wordScramble: return "\(value)/10 words"
        case .memoryChain: return "Chain \(value)"
        default: return "\(value)"
        }
    }

    private func formatTotalTime() -> String {
        let totalSeconds = exercises.reduce(0) { $0 + $1.durationSeconds }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
