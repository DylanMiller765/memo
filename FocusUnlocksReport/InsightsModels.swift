//
//  InsightsModels.swift
//  Shared by the MindRestore app and the FocusUnlocksReport extension.
//
//  The Insights week data (built by the Screen Time report) and the pure copy
//  logic the week view uses. The app uses them for the screenshot stand-in and tests.
//

import Foundation
import ManagedSettings

enum FocusInsightsDayState: Hashable {
    case low
    case normal
    case high
    case noData
}

enum FocusInsightsOffenderIcon: Hashable {
    case application(ApplicationToken)
    case category(ActivityCategoryToken)
    case webDomain(WebDomainToken)
    case fallback
}

struct FocusInsightsDay: Identifiable, Hashable {
    let id: Int
    let date: Date
    let seconds: TimeInterval
    let pickups: Int
    let hourlySeconds: [TimeInterval]
    let state: FocusInsightsDayState
}

struct FocusInsightsOffender: Identifiable, Hashable {
    let id: String
    let name: String
    let seconds: TimeInterval
    let icon: FocusInsightsOffenderIcon
}

struct FocusInsightsConfiguration: Hashable {
    let days: [FocusInsightsDay]
    let weeklyOffenders: [FocusInsightsOffender]
    let dailyOffenders: [[FocusInsightsOffender]]
    let generatedAt: Date

    var totalSeconds: TimeInterval {
        days.reduce(0) { $0 + $1.seconds }
    }

    var averageSeconds: TimeInterval {
        guard !days.isEmpty else { return 0 }
        return totalSeconds / Double(days.count)
    }

    var totalPickups: Int {
        days.reduce(0) { $0 + $1.pickups }
    }

    var peakDay: FocusInsightsDay? {
        days.max { $0.seconds < $1.seconds }
    }
}

/// Copy and mood for the Insights hero, for the whole week or one selected day.
struct InsightsWeekSummary: Equatable {
    let headline: String
    /// Drives Memo's face: low = happy, high = sad, otherwise neutral.
    let mood: FocusInsightsDayState

    static func week(_ configuration: FocusInsightsConfiguration, calendar: Calendar = .current) -> InsightsWeekSummary {
        let logged = configuration.days.filter { $0.seconds > 0 }
        guard !logged.isEmpty else { return InsightsWeekSummary(headline: "Your week starts here.", mood: .normal) }
        let mood = logged.last?.state ?? .normal
        guard logged.count > 1, let best = logged.min(by: { $0.seconds < $1.seconds }) else {
            return InsightsWeekSummary(headline: "Day one is on the board.", mood: mood)
        }
        return InsightsWeekSummary(headline: "\(weekday(best.date, calendar)) was your best day.", mood: mood)
    }

    static func day(_ day: FocusInsightsDay, average: TimeInterval, calendar: Calendar = .current) -> InsightsWeekSummary {
        guard day.seconds > 0 else { return InsightsWeekSummary(headline: "No screen time logged.", mood: .normal) }
        let name = weekday(day.date, calendar)
        let diff = day.seconds - average
        if abs(diff) < 5 * 60 {
            return InsightsWeekSummary(headline: "\(name) was right on your average.", mood: .normal)
        }
        if diff < 0 {
            return InsightsWeekSummary(headline: "\(name) was \(duration(-diff)) under your average.", mood: .low)
        }
        return InsightsWeekSummary(headline: "\(name) ran \(duration(diff)) over your average.", mood: .high)
    }

    /// "42m", "3h 07m", "26h 00m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// The day's busiest hour, e.g. "9 PM"; nil when nothing was logged.
    static func peakHour(_ day: FocusInsightsDay) -> String? {
        guard let peak = day.hourlySeconds.indices.max(by: { day.hourlySeconds[$0] < day.hourlySeconds[$1] }),
              day.hourlySeconds[peak] > 0 else { return nil }
        let hour12 = peak % 12 == 0 ? 12 : peak % 12
        return "\(hour12) \(peak < 12 ? "AM" : "PM")"
    }

    private static func weekday(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
