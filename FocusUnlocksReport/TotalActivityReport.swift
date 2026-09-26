//
//  TotalActivityReport.swift
//  FocusUnlocksReport
//

import DeviceActivity
import ExtensionKit
import Foundation
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    /// Yesterday's phone-unlock (pickup) count.
    static let unlocks = Self("Unlocks Count")
    /// Yesterday's total screen time (in hours).
    static let screenTime = Self("Screen Time")
    /// Average daily screen time over the configured multi-day window.
    static let screenTimeAverage = Self("Screen Time Daily Average")
    /// Daily screen-time bars for the 7-day window ending yesterday.
    static let screenTimeWeekly = Self("Screen Time Weekly")
    /// Onboarding receipt: total Screen Time over the last 7 full days.
    static let onboardingScreenTimeWeekTotal = Self("Onboarding Screen Time Week Total")
    /// Today's Home screen receipt: total time, pickups, and top offenders.
    static let focusHomeDashboard = Self("Focus Home Dashboard")
    /// Interactive Focus Insights report with real Screen Time drilldowns.
    static let focusInsightsInteractive = Self("Focus Insights Interactive")
    /// Home hill: Screen time + Pickups tiles for today.
    static let homeStats = Self("Home Stats")
    /// Home hill: today's top 3 apps (shown while blocking is off).
    static let homeTopOffenders = Self("Home Top Offenders")
}

struct FocusHomeDashboardConfiguration: Hashable {
    let totalSeconds: TimeInterval
    let pickups: Int
    let offenders: [FocusInsightsOffender]
}

struct OnboardingWeeklyScreenTimeConfiguration: Hashable {
    let totalHours: Double
    let dailyAverageHours: Double
}

private struct FocusInsightsOffenderAccumulator {
    var name: String
    var seconds: TimeInterval
    var icon: FocusInsightsOffenderIcon
}

/// Sums phone pickups across all apps + pickups-without-app-activity.
struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .unlocks
    let content: (Int) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        var total = 0
        for await activity in data {
            for await segment in activity.activitySegments {
                total += segment.totalPickupsWithoutApplicationActivity
                for await category in segment.categories {
                    for await app in category.applications {
                        total += app.numberOfPickups
                    }
                }
            }
        }
        UserDefaults(suiteName: "group.com.memori.shared")?.set(total, forKey: "onboarding_yesterday_unlocks")
        return total
    }
}

/// Total screen-time duration for the configured filter window, returned as hours (Double).
struct ScreenTimeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenTime
    let content: (Double) -> ScreenTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Double {
        var totalSeconds: TimeInterval = 0
        for await activity in data {
            for await segment in activity.activitySegments {
                totalSeconds += segment.totalActivityDuration
            }
        }
        let hours = totalSeconds / 3600.0
        return hours
    }
}

/// Average screen-time duration per day for the configured filter window.
struct ScreenTimeAverageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenTimeAverage
    let content: (Double) -> ScreenTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Double {
        var totalSeconds: TimeInterval = 0
        var segmentCount = 0

        for await activity in data {
            for await segment in activity.activitySegments {
                totalSeconds += segment.totalActivityDuration
                segmentCount += 1
            }
        }

        let averageHours = (totalSeconds / Double(max(segmentCount, 1))) / 3600.0
        return averageHours
    }
}

/// Daily screen-time totals for the configured 7-day window, returned as hours.
struct ScreenTimeWeeklyReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenTimeWeekly
    let content: ([Double]) -> WeeklyScreenTimeChartView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [Double] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        var totalsByDay: [Date: TimeInterval] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                totalsByDay[day, default: 0] += segment.totalActivityDuration
            }
        }

        let dailyHours = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: windowStart) ?? windowStart
            return (totalsByDay[day] ?? 0) / 3600.0
        }

        return dailyHours
    }
}

/// Visible onboarding Screen Time receipt. Display-only: the report sandbox
/// cannot pass usage data back to the app, so the user confirms the total
/// via the match slider on the onboarding page instead.
struct OnboardingWeeklyScreenTimeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .onboardingScreenTimeWeekTotal
    let content: (OnboardingWeeklyScreenTimeConfiguration) -> OnboardingWeeklyScreenTimeView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> OnboardingWeeklyScreenTimeConfiguration {
        var totalSeconds: TimeInterval = 0

        for await activity in data {
            for await segment in activity.activitySegments {
                totalSeconds += segment.totalActivityDuration
            }
        }

        let totalHours = totalSeconds / 3600.0
        let dailyAverageHours = totalHours / 7.0

        return OnboardingWeeklyScreenTimeConfiguration(
            totalHours: totalHours,
            dailyAverageHours: dailyAverageHours
        )
    }
}

/// Today's totals and every offender, sorted by time. Shared by the Home scenes.
enum HomeDayActivity {
    static func collect(_ data: DeviceActivityResults<DeviceActivityData>) async -> FocusHomeDashboardConfiguration {
        var totalSeconds: TimeInterval = 0
        var pickups = 0
        var offenders: [String: FocusInsightsOffenderAccumulator] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                totalSeconds += segment.totalActivityDuration
                pickups += segment.totalPickupsWithoutApplicationActivity

                for await category in segment.categories {
                    var childSeconds: TimeInterval = 0

                    for await app in category.applications {
                        let seconds = app.totalActivityDuration
                        guard seconds > 0 else { continue }
                        childSeconds += seconds
                        pickups += app.numberOfPickups

                        let name = app.application.localizedDisplayName
                            ?? app.application.bundleIdentifier
                            ?? "App"
                        let token = app.application.token
                        let key = app.application.bundleIdentifier
                            ?? token.map { "app:\(String(describing: $0))" }
                            ?? "app:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.application) ?? .fallback
                        offenders[key, default: FocusInsightsOffenderAccumulator(name: name, seconds: 0, icon: icon)].seconds += seconds
                    }

                    for await webDomain in category.webDomains {
                        let seconds = webDomain.totalActivityDuration
                        guard seconds > 0 else { continue }
                        childSeconds += seconds

                        let name = webDomain.webDomain.domain ?? "Website"
                        let token = webDomain.webDomain.token
                        let key = token.map { "web:\(String(describing: $0))" } ?? "web:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.webDomain) ?? .fallback
                        offenders[key, default: FocusInsightsOffenderAccumulator(name: name, seconds: 0, icon: icon)].seconds += seconds
                    }

                    if childSeconds == 0, category.totalActivityDuration > 0 {
                        let name = category.category.localizedDisplayName ?? "Category"
                        let token = category.category.token
                        let key = token.map { "category:\(String(describing: $0))" } ?? "category:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.category) ?? .fallback
                        offenders[key, default: FocusInsightsOffenderAccumulator(name: name, seconds: 0, icon: icon)].seconds += category.totalActivityDuration
                    }
                }
            }
        }

        let sorted = offenders.map { key, value in
            FocusInsightsOffender(id: key, name: value.name, seconds: value.seconds, icon: value.icon)
        }
        .filter { $0.seconds > 0 }
        .sorted { $0.seconds > $1.seconds }

        return FocusHomeDashboardConfiguration(totalSeconds: totalSeconds, pickups: pickups, offenders: sorted)
    }
}

/// Compact real Screen Time receipt shown on Home above the Memo control state.
struct FocusHomeDashboardReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .focusHomeDashboard
    let content: (FocusHomeDashboardConfiguration) -> FocusHomeDashboardView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> FocusHomeDashboardConfiguration {
        let all = await HomeDayActivity.collect(data)
        return FocusHomeDashboardConfiguration(
            totalSeconds: all.totalSeconds,
            pickups: all.pickups,
            offenders: Array(all.offenders.prefix(3))
        )
    }
}

/// Home hill: the Screen time + Pickups tiles.
struct HomeStatsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .homeStats
    let content: (FocusHomeDashboardConfiguration) -> HomeStatsTilesView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> FocusHomeDashboardConfiguration {
        await HomeDayActivity.collect(data)
    }
}

/// Home hill: today's top 3 apps while blocking is off.
struct HomeTopOffendersReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .homeTopOffenders
    let content: (FocusHomeDashboardConfiguration) -> HomeTopOffendersView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> FocusHomeDashboardConfiguration {
        let all = await HomeDayActivity.collect(data)
        return FocusHomeDashboardConfiguration(
            totalSeconds: all.totalSeconds,
            pickups: all.pickups,
            offenders: Array(all.offenders.prefix(3))
        )
    }
}

/// Full Focus Insights report. This stays inside the DeviceActivity extension so
/// app names/icons are rendered from Screen Time data instead of exported.
struct FocusInsightsInteractiveReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .focusInsightsInteractive
    let content: (FocusInsightsConfiguration) -> InsightsWeekView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> FocusInsightsConfiguration {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let dayDates = (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: windowStart) ?? windowStart
        }

        var secondsByDay = Dictionary(uniqueKeysWithValues: dayDates.map { ($0, TimeInterval(0)) })
        var pickupsByDay = Dictionary(uniqueKeysWithValues: dayDates.map { ($0, 0) })
        var hourlyByDay = Dictionary(uniqueKeysWithValues: dayDates.map { ($0, Array(repeating: TimeInterval(0), count: 24)) })
        var weeklyOffenders: [String: FocusInsightsOffenderAccumulator] = [:]
        var dailyOffenders = Dictionary(uniqueKeysWithValues: dayDates.map { ($0, [String: FocusInsightsOffenderAccumulator]()) })

        for await activity in data {
            for await segment in activity.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                guard secondsByDay[day] != nil else { continue }

                secondsByDay[day, default: 0] += segment.totalActivityDuration
                pickupsByDay[day, default: 0] += segment.totalPickupsWithoutApplicationActivity

                let hour = calendar.component(.hour, from: segment.dateInterval.start)
                if hourlyByDay[day]?.indices.contains(hour) == true {
                    hourlyByDay[day]?[hour] += segment.totalActivityDuration
                }

                for await category in segment.categories {
                    var childSeconds: TimeInterval = 0

                    for await app in category.applications {
                        let seconds = app.totalActivityDuration
                        guard seconds > 0 else { continue }
                        childSeconds += seconds
                        pickupsByDay[day, default: 0] += app.numberOfPickups

                        let name = app.application.localizedDisplayName
                            ?? app.application.bundleIdentifier
                            ?? "App"
                        let token = app.application.token
                        let key = app.application.bundleIdentifier
                            ?? token.map { "app:\(String(describing: $0))" }
                            ?? "app:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.application) ?? .fallback
                        addOffender(
                            key: key,
                            name: name,
                            seconds: seconds,
                            icon: icon,
                            weekly: &weeklyOffenders,
                            daily: &dailyOffenders[day, default: [:]]
                        )
                    }

                    for await webDomain in category.webDomains {
                        let seconds = webDomain.totalActivityDuration
                        guard seconds > 0 else { continue }
                        childSeconds += seconds

                        let name = webDomain.webDomain.domain ?? "Website"
                        let token = webDomain.webDomain.token
                        let key = token.map { "web:\(String(describing: $0))" } ?? "web:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.webDomain) ?? .fallback
                        addOffender(
                            key: key,
                            name: name,
                            seconds: seconds,
                            icon: icon,
                            weekly: &weeklyOffenders,
                            daily: &dailyOffenders[day, default: [:]]
                        )
                    }

                    if childSeconds == 0, category.totalActivityDuration > 0 {
                        let name = category.category.localizedDisplayName ?? "Category"
                        let token = category.category.token
                        let key = token.map { "category:\(String(describing: $0))" } ?? "category:\(name)"
                        let icon = token.map(FocusInsightsOffenderIcon.category) ?? .fallback
                        addOffender(
                            key: key,
                            name: name,
                            seconds: category.totalActivityDuration,
                            icon: icon,
                            weekly: &weeklyOffenders,
                            daily: &dailyOffenders[day, default: [:]]
                        )
                    }
                }
            }
        }

        let average = secondsByDay.values.reduce(0, +) / Double(max(dayDates.count, 1))
        let days = dayDates.enumerated().map { index, date in
            let seconds = secondsByDay[date] ?? 0
            return FocusInsightsDay(
                id: index,
                date: date,
                seconds: seconds,
                pickups: pickupsByDay[date] ?? 0,
                hourlySeconds: hourlyByDay[date] ?? Array(repeating: 0, count: 24),
                state: dayState(seconds: seconds, average: average)
            )
        }

        return FocusInsightsConfiguration(
            days: days,
            weeklyOffenders: sortedOffenders(weeklyOffenders),
            dailyOffenders: dayDates.map { sortedOffenders(dailyOffenders[$0] ?? [:]) },
            generatedAt: .now
        )
    }

    private func addOffender(
        key: String,
        name: String,
        seconds: TimeInterval,
        icon: FocusInsightsOffenderIcon,
        weekly: inout [String: FocusInsightsOffenderAccumulator],
        daily: inout [String: FocusInsightsOffenderAccumulator]
    ) {
        weekly[key, default: FocusInsightsOffenderAccumulator(name: name, seconds: 0, icon: icon)].seconds += seconds
        daily[key, default: FocusInsightsOffenderAccumulator(name: name, seconds: 0, icon: icon)].seconds += seconds
    }

    private func sortedOffenders(_ offenders: [String: FocusInsightsOffenderAccumulator]) -> [FocusInsightsOffender] {
        offenders.map { key, value in
            FocusInsightsOffender(id: key, name: value.name, seconds: value.seconds, icon: value.icon)
        }
        .filter { $0.seconds > 0 }
        .sorted { $0.seconds > $1.seconds }
    }

    private func dayState(seconds: TimeInterval, average: TimeInterval) -> FocusInsightsDayState {
        guard seconds > 0, average > 0 else { return .noData }
        if seconds >= average * 1.10 { return .high }
        if seconds <= average * 0.90 { return .low }
        return .normal
    }
}
