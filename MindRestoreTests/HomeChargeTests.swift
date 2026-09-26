import XCTest
@testable import MindRestore

final class HomeChargeTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func d(_ day: Int, _ hour: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }

    func testPercentMapping() {
        XCTAssertEqual(HomeCharge.make(gamesToday: 0, lastSessionDate: d(25), now: d(26), calendar: cal).percent, 0)
        XCTAssertEqual(HomeCharge.make(gamesToday: 1, lastSessionDate: d(26), now: d(26), calendar: cal).percent, 33)
        XCTAssertEqual(HomeCharge.make(gamesToday: 2, lastSessionDate: d(26), now: d(26), calendar: cal).percent, 67)
        XCTAssertEqual(HomeCharge.make(gamesToday: 5, lastSessionDate: d(26), now: d(26), calendar: cal).percent, 100)
    }
    func testTiers() {
        XCTAssertEqual(HomeCharge.make(gamesToday: 3, lastSessionDate: d(26), now: d(26), calendar: cal).tier, .glow)
        XCTAssertEqual(HomeCharge.make(gamesToday: 2, lastSessionDate: d(26), now: d(26), calendar: cal).tier, .calm)
        XCTAssertEqual(HomeCharge.make(gamesToday: 1, lastSessionDate: d(26), now: d(26), calendar: cal).tier, .dim)
        XCTAssertEqual(HomeCharge.make(gamesToday: 0, lastSessionDate: d(25), now: d(26), calendar: cal).tier, .dim)
        XCTAssertEqual(HomeCharge.make(gamesToday: 0, lastSessionDate: d(24), now: d(26), calendar: cal).tier, .rain(days: 2))
        XCTAssertEqual(HomeCharge.make(gamesToday: 0, lastSessionDate: d(20), now: d(26), calendar: cal).tier, .rain(days: 6))
    }
    func testNewUserIsDimNotRain() {
        let c = HomeCharge.make(gamesToday: 0, lastSessionDate: nil, now: d(26), calendar: cal)
        XCTAssertEqual(c.tier, .dim); XCTAssertEqual(c.mood, .neutral)
    }
    func testMidnightRolloverDropsYesterdaysGlow() {
        // Yesterday's 3 games don't count today: HomeView passes today's count (0), last session yesterday → dim.
        let c = HomeCharge.make(gamesToday: 0, lastSessionDate: d(25, 23), now: d(26, 0), calendar: cal)
        XCTAssertEqual(c.tier, .dim); XCTAssertEqual(c.percent, 0)
    }
    func testMoodAndCopy() {
        let glow = HomeCharge.make(gamesToday: 3, lastSessionDate: d(26), now: d(26), calendar: cal)
        XCTAssertEqual(glow.mood, .happy); XCTAssertEqual(glow.line, "Fully charged. See you tomorrow.")
        XCTAssertEqual(HomeCharge.make(gamesToday: 2, lastSessionDate: d(26), now: d(26), calendar: cal).line, "1 more game for 100%.")
        XCTAssertEqual(HomeCharge.make(gamesToday: 1, lastSessionDate: d(26), now: d(26), calendar: cal).line, "2 more games to charge Memo up.")
        XCTAssertEqual(HomeCharge.make(gamesToday: 0, lastSessionDate: d(25), now: d(26), calendar: cal).line, "3 more games to charge Memo up.")
        let rain = HomeCharge.make(gamesToday: 0, lastSessionDate: d(24), now: d(26), calendar: cal)
        XCTAssertEqual(rain.mood, .sad); XCTAssertEqual(rain.line, "Memo's been rained on for 2 days. Play 1 game.")
        for g in 0...3 {
            let line = HomeCharge.make(gamesToday: g, lastSessionDate: d(20), now: d(26), calendar: cal).line.lowercased()
            XCTAssertFalse(line.contains("win")); XCTAssertFalse(line.contains("bet"))
        }
    }
    func testPayoffMemory() {
        let ud = UserDefaults(suiteName: "HomeChargeTests")!; ud.removePersistentDomain(forName: "HomeChargeTests")
        XCTAssertNil(HomeChargeMemory.payoffStart(current: 33, now: d(26, 9), defaults: ud, calendar: cal))   // first sighting: no payoff
        XCTAssertEqual(HomeChargeMemory.payoffStart(current: 67, now: d(26, 10), defaults: ud, calendar: cal), 33)
        XCTAssertNil(HomeChargeMemory.payoffStart(current: 67, now: d(26, 11), defaults: ud, calendar: cal))  // no replay
        XCTAssertNil(HomeChargeMemory.payoffStart(current: 33, now: d(27, 9), defaults: ud, calendar: cal))   // new day resets
    }
}
