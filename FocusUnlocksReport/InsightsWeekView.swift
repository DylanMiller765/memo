//
//  InsightsWeekView.swift
//  Shared by the MindRestore app (screenshot stand-in) and the FocusUnlocksReport extension (real data).
//
//  Insights "A4": a compact hero (total + Memo + verdict), the week as Memo faces standing on
//  the hill the app draws behind this view, sticker tiles, a chunky bar chart and top offenders.
//  Tap a face for that day's breakdown; tap it again (or "Week") to go back.
//

import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

struct InsightsWeekView: View {
    let configuration: FocusInsightsConfiguration

    /// Heights the app uses to put the hill crest under the faces row.
    static let heroHeight: CGFloat = 178
    static let facesHeight: CGFloat = 88

    @State private var selectedDayID: Int?
    @State private var showingTopTen = false

    init(configuration: FocusInsightsConfiguration, initialDayID: Int? = nil) {
        self.configuration = configuration
        _selectedDayID = State(initialValue: initialDayID)
    }

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)
    private static let mint = Color(red: 0.482, green: 0.89, blue: 0.776)
    private static let amber = Color(red: 1, green: 0.827, blue: 0.42)
    private static let coral = Color(red: 1, green: 0.541, blue: 0.478)
    private static let tileFill = Color(red: 0, green: 0.086, blue: 0.11).opacity(0.42)
    private static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var selectedDay: FocusInsightsDay? {
        guard let selectedDayID else { return nil }
        return configuration.days.first { $0.id == selectedDayID }
    }

    private var summary: InsightsWeekSummary {
        if let selectedDay {
            return InsightsWeekSummary.day(selectedDay, average: configuration.averageSeconds)
        }
        return InsightsWeekSummary.week(configuration)
    }

    private var offenders: [FocusInsightsOffender] {
        if let selectedDayID, configuration.dailyOffenders.indices.contains(selectedDayID) {
            return configuration.dailyOffenders[selectedDayID]
        }
        return configuration.weeklyOffenders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .frame(height: Self.heroHeight, alignment: .top)
            weekFaces
                .frame(height: Self.facesHeight, alignment: .top)
            tiles
                .padding(.top, 14)
            if !showingTopTen {
                chartCard
                    .padding(.top, 16)
            }
            offendersSection
                .padding(.top, 22)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.25), value: selectedDayID)
        .animation(.snappy(duration: 0.25), value: showingTopTen)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(heroEyebrow)
                        .font(InsightsFont.heavy(12))
                        .foregroundStyle(.white.opacity(0.75))
                    if selectedDay != nil {
                        Button {
                            selectedDayID = nil
                            showingTopTen = false
                        } label: {
                            Text("Week")
                                .font(InsightsFont.heavy(11))
                                .foregroundStyle(Self.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Self.mint, in: Capsule())
                                .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to the whole week")
                    }
                }

                InsightsOutlinedText(text: InsightsWeekSummary.duration(selectedDay?.seconds ?? configuration.totalSeconds), size: 50)
                    .padding(.top, 2)
                    .contentTransition(.numericText())

                Text(summary.headline)
                    .font(InsightsFont.heavy(13))
                    .foregroundStyle(Self.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Self.ink, lineWidth: 2))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.ink).offset(y: 3))
                    .padding(.top, 12)
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            Spacer(minLength: 0)

            MemoFaceImage(state: summary.mood, fallbackToNeutral: true)
                .frame(width: 128, height: 128)
                .offset(y: 4)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
    }

    private var heroEyebrow: String {
        guard let selectedDay else { return "ON YOUR PHONE" }
        return selectedDay.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }

    // MARK: - The week on the hill

    private static let faceLift: [CGFloat] = [18, 9, 3, 0, 3, 9, 18]

    private var weekFaces: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(configuration.days.enumerated()), id: \.element.id) { index, day in
                let selected = selectedDayID == day.id
                Button {
                    selectedDayID = selected ? nil : day.id
                    showingTopTen = false
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: -4) {
                        MemoFaceImage(state: day.state, fallbackToNeutral: false)
                            .frame(width: selected ? 52 : 44, height: selected ? 52 : 44)
                            .opacity(day.state == .noData ? 0.45 : 1)
                        Text(selected ? "\(dayLetter(day)) · \(InsightsWeekSummary.duration(day.seconds))" : dayLetter(day))
                            .font(InsightsFont.heavy(11))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(selected ? Self.ink : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(selected ? Color.white : Color(red: 0, green: 0.086, blue: 0.11).opacity(0.55), in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Self.ink : Color.white.opacity(0.15), lineWidth: selected ? 2 : 1))
                            .background(Capsule().fill(selected ? Self.ink : .clear).offset(y: 2))
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: Self.faceLift[min(index, Self.faceLift.count - 1)])
                    .zIndex(selected ? 1 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(InsightsWeekSummary.duration(day.seconds))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func dayLetter(_ day: FocusInsightsDay) -> String {
        String(day.date.formatted(.dateTime.weekday(.narrow)))
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            if let selectedDay {
                let diff = selectedDay.seconds - configuration.averageSeconds
                tile(.clock, value: (diff < 0 ? "−" : "+") + InsightsWeekSummary.duration(abs(diff)), label: "vs average")
                tile(.phone, value: "\(selectedDay.pickups)", label: "Pickups")
                tile(.flame, value: InsightsWeekSummary.peakHour(selectedDay) ?? "—", label: "Busiest hour")
            } else {
                tile(.clock, value: InsightsWeekSummary.duration(configuration.averageSeconds), label: "Daily avg")
                tile(.phone, value: "\(configuration.totalPickups)", label: "Pickups")
                tile(.flame, value: peakDayLabel, label: "Peak day")
            }
        }
    }

    private var peakDayLabel: String {
        guard let peak = configuration.peakDay, peak.seconds > 0 else { return "—" }
        return peak.date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func tile(_ kind: StickerKind, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            StickerIcon(kind: kind, size: 36)
            Text(value)
                .font(InsightsFont.heavy(19))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(InsightsFont.semibold(11))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Self.tileFill, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDay == nil ? "Per day" : "By 3 hours")
                    .font(InsightsFont.heavy(17))
                    .foregroundStyle(.white)
                Spacer()
                Text("avg \(InsightsWeekSummary.duration(configuration.averageSeconds))")
                    .font(InsightsFont.heavy(12))
                    .foregroundStyle(Self.mint)
            }
            if let selectedDay {
                barChart(bars: threeHourBars(selectedDay), average: nil)
            } else {
                barChart(bars: weekBars, average: configuration.averageSeconds)
            }
        }
        .padding(14)
        .background(Self.tileFill, in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var weekBars: [(String, TimeInterval, Color)] {
        configuration.days.map { day -> (String, TimeInterval, Color) in
            let label = day.date.formatted(.dateTime.weekday(.narrow))
            return (label, day.seconds, color(for: day.state))
        }
    }

    private func threeHourBars(_ day: FocusInsightsDay) -> [(String, TimeInterval, Color)] {
        let labels = ["12a", "3a", "6a", "9a", "12p", "3p", "6p", "9p"]
        var sums = Array(repeating: TimeInterval(0), count: 8)
        for (hour, seconds) in day.hourlySeconds.enumerated() where hour < 24 {
            sums[hour / 3] += seconds
        }
        let peak = sums.max() ?? 0
        return sums.enumerated().map { index, value in
            (labels[index], value, value > 0 && value == peak ? Self.coral : Self.mint)
        }
    }

    private func barChart(bars: [(String, TimeInterval, Color)], average: TimeInterval?) -> some View {
        let plotHeight: CGFloat = 120
        let maxValue = max(bars.map(\.1).max() ?? 0, average ?? 0, 60)
        return ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 6) {
                        let height = max(bar.1 > 0 ? 8 : 4, plotHeight * CGFloat(bar.1 / maxValue))
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(bar.1 > 0 ? bar.2 : Color.white.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Self.ink, lineWidth: bar.1 > 0 ? 2 : 0))
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.ink).offset(y: bar.1 > 0 ? 3 : 0))
                            .frame(height: height)
                        Text(bar.0)
                            .font(InsightsFont.heavy(11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let average, average > 0 {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: 0.5)
                    .padding(.bottom, 21 + plotHeight * CGFloat(average / maxValue))
            }
        }
        .frame(height: plotHeight + 21, alignment: .bottom)
    }

    private func color(for state: FocusInsightsDayState) -> Color {
        switch state {
        case .low: return Self.mint
        case .normal: return Self.amber
        case .high: return Self.coral
        case .noData: return Color.white.opacity(0.14)
        }
    }

    // MARK: - Offenders

    private var offendersSection: some View {
        let shown = Array(offenders.prefix(showingTopTen ? 10 : 4))
        let top = max(shown.first?.seconds ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top offenders")
                    .font(InsightsFont.heavy(19))
                    .foregroundStyle(.white)
                Spacer()
                if offenders.count > 4 {
                    Button(showingTopTen ? "Show less" : "See top 10") { showingTopTen.toggle() }
                        .font(InsightsFont.bold(13))
                        .foregroundStyle(.white.opacity(0.6))
                        .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                if shown.isEmpty {
                    Text("No app time logged yet")
                        .font(InsightsFont.bold(14))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, offender in
                    if index > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 64)
                    }
                    HStack(spacing: 12) {
                        offenderIcon(offender)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(offender.name)
                                    .font(InsightsFont.heavy(15))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if index == 0 {
                                    Text("MOST")
                                        .font(InsightsFont.heavy(9))
                                        .foregroundStyle(Self.ink)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Self.coral, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Self.ink, lineWidth: 1.2))
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.1))
                                    Capsule().fill(Self.coral).frame(width: max(6, geo.size.width * CGFloat(offender.seconds / top)))
                                }
                            }
                            .frame(height: 6)
                        }
                        Text(InsightsWeekSummary.duration(offender.seconds))
                            .font(InsightsFont.heavy(15))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Self.tileFill, in: Self.cardShape)
            .overlay(Self.cardShape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func offenderIcon(_ offender: FocusInsightsOffender) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch offender.icon {
        case .application(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .category(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .webDomain(let token):
            Label(token).labelStyle(.iconOnly).frame(width: 38, height: 38).clipShape(shape)
        case .fallback:
            // The app's stand-in data names real apps; their logos live in the app's asset catalog.
            if let logo = UIImage(named: "logo-\(offender.name.lowercased())") {
                Image(uiImage: logo).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(shape)
            } else {
                shape.fill(Color.white.opacity(0.12)).frame(width: 38, height: 38)
                    .overlay(StickerIcon(kind: .phone, size: 26))
            }
        }
    }
}

// MARK: - Pieces

/// Memo for a day state, rendered from the Rive poses: happy (light day), neutral, sad (heavy day).
private struct MemoFaceImage: View {
    let state: FocusInsightsDayState
    /// The hero shows neutral for "no data"; the week strip shows the neutral face dimmed.
    let fallbackToNeutral: Bool

    private var name: String {
        switch state {
        case .low: return "insights-memo-happy"
        case .high: return "insights-memo-sad"
        case .normal, .noData: return "insights-memo-neutral"
        }
    }

    var body: some View {
        // App: asset catalog. Extension: loose PNG in its bundle.
        if let image = UIImage(named: name) ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:)) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            StickerIcon(kind: .person, size: 36)
        }
    }
}

/// White heavy text with a dark sticker outline.
private struct InsightsOutlinedText: View {
    let text: String
    let size: CGFloat

    private static let ink = Color(red: 0.043, green: 0.106, blue: 0.133)

    var body: some View {
        let d: CGFloat = 3
        let offsets = [CGSize(width: d, height: 0), CGSize(width: -d, height: 0), CGSize(width: 0, height: d), CGSize(width: 0, height: -d),
                       CGSize(width: 2, height: 2), CGSize(width: -2, height: -2), CGSize(width: 2, height: -2), CGSize(width: -2, height: 2)]
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).foregroundStyle(Self.ink).offset(offsets[i])
            }
            Text(text).foregroundStyle(.white)
        }
        .font(InsightsFont.heavy(size))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .shadow(color: .black.opacity(0.25), radius: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Bricolage Grotesque (bundled in both the app and the extension).
enum InsightsFont {
    static func heavy(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-ExtraBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-Bold", size: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-SemiBold", size: size) }
}

// MARK: - Demo week (screenshots, previews)

extension FocusInsightsConfiguration {
    /// A realistic week for screenshots and previews, ending today.
    static func demo(now: Date = .now, calendar: Calendar = .current) -> FocusInsightsConfiguration {
        let minutes: [Double] = [262, 248, 231, 239, 214, 176, 190]
        let states: [FocusInsightsDayState] = [.high, .high, .normal, .normal, .normal, .low, .low]
        let today = calendar.startOfDay(for: now)
        let days = minutes.enumerated().map { index, m -> FocusInsightsDay in
            var hourly = Array(repeating: TimeInterval(0), count: 24)
            for (hour, share) in [(8, 0.08), (12, 0.14), (13, 0.1), (17, 0.12), (20, 0.2), (21, 0.24), (22, 0.12)] {
                hourly[hour] = m * 60 * share
            }
            return FocusInsightsDay(
                id: index,
                date: calendar.date(byAdding: .day, value: index - 6, to: today) ?? today,
                seconds: m * 60,
                pickups: [66, 63, 58, 61, 55, 52, 57][index],
                hourlySeconds: hourly,
                state: states[index]
            )
        }
        let apps: [(String, Double)] = [("TikTok", 552), ("Instagram", 400), ("YouTube", 245), ("Snapchat", 138), ("X", 96)]
        let offenders = apps.map { FocusInsightsOffender(id: $0.0, name: $0.0, seconds: $0.1 * 60, icon: .fallback) }
        let daily = days.map { day in
            apps.prefix(4).map { FocusInsightsOffender(id: $0.0, name: $0.0, seconds: day.seconds * $0.1 / 1431, icon: .fallback) }
        }
        return FocusInsightsConfiguration(days: days, weeklyOffenders: offenders, dailyOffenders: daily, generatedAt: now)
    }
}

#Preview {
    ScrollView {
        InsightsWeekView(configuration: .demo())
    }
    .background(Color(red: 0, green: 0.17, blue: 0.2))
}
