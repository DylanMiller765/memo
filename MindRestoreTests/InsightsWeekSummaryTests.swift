import XCTest
@testable import MindRestore

final class InsightsWeekSummaryTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: day))! }
    private func day(_ id: Int, _ dom: Int, minutes: Double, state: FocusInsightsDayState = .normal, hourly: [TimeInterval]? = nil) -> FocusInsightsDay {
        FocusInsightsDay(id: id, date: date(dom), seconds: minutes * 60, pickups: 10,
                         hourlySeconds: hourly ?? Array(repeating: 0, count: 24), state: state)
    }
    private func config(_ days: [FocusInsightsDay]) -> FocusInsightsConfiguration {
        FocusInsightsConfiguration(days: days, weeklyOffenders: [], dailyOffenders: days.map { _ in [] }, generatedAt: date(26))
    }

    func testWeekNamesBestDayAndUsesLatestDayForMood() {
        let c = config([day(0, 24, minutes: 250, state: .high), day(1, 25, minutes: 176, state: .low), day(2, 26, minutes: 190, state: .low)])
        let s = InsightsWeekSummary.week(c, calendar: cal)
        XCTAssertEqual(s.headline, "Friday was your best day.")
        XCTAssertEqual(s.mood, .low)
    }
    func testWeekWithNoDataOrOneDay() {
        XCTAssertEqual(InsightsWeekSummary.week(config([day(0, 26, minutes: 0, state: .noData)]), calendar: cal).headline, "Your week starts here.")
        XCTAssertEqual(InsightsWeekSummary.week(config([day(0, 25, minutes: 0, state: .noData), day(1, 26, minutes: 90)]), calendar: cal).headline, "Day one is on the board.")
    }
    func testDayVersusAverage() {
        let under = InsightsWeekSummary.day(day(5, 25, minutes: 176, state: .low), average: 222 * 60, calendar: cal)
        XCTAssertEqual(under.headline, "Friday was 46m under your average.")
        XCTAssertEqual(under.mood, .low)
        let over = InsightsWeekSummary.day(day(0, 20, minutes: 262 + 60, state: .high), average: 222 * 60, calendar: cal)
        XCTAssertEqual(over.headline, "Sunday ran 1h 40m over your average.")
        XCTAssertEqual(over.mood, .high)
        XCTAssertEqual(InsightsWeekSummary.day(day(3, 23, minutes: 224), average: 222 * 60, calendar: cal).headline, "Wednesday was right on your average.")
        XCTAssertEqual(InsightsWeekSummary.day(day(3, 23, minutes: 0, state: .noData), average: 222 * 60, calendar: cal).headline, "No screen time logged.")
    }
    func testDurationsAndPeakHour() {
        XCTAssertEqual(InsightsWeekSummary.duration(42 * 60), "42m")
        XCTAssertEqual(InsightsWeekSummary.duration(26 * 3600), "26h 00m")
        XCTAssertEqual(InsightsWeekSummary.duration(3 * 3600 + 7 * 60), "3h 07m")
        var hourly = Array(repeating: TimeInterval(0), count: 24); hourly[21] = 1200; hourly[8] = 600
        XCTAssertEqual(InsightsWeekSummary.peakHour(day(0, 26, minutes: 30, hourly: hourly)), "9 PM")
        XCTAssertNil(InsightsWeekSummary.peakHour(day(0, 26, minutes: 0, state: .noData)))
    }
    func testCopyNeverSaysWinOrBet() {
        let lines = [InsightsWeekSummary.week(config([day(0, 25, minutes: 100), day(1, 26, minutes: 90)]), calendar: cal).headline,
                     InsightsWeekSummary.day(day(1, 26, minutes: 90), average: 95 * 60, calendar: cal).headline]
        for l in lines { XCTAssertFalse(l.lowercased().contains("win")); XCTAssertFalse(l.lowercased().contains("bet")) }
    }
}
