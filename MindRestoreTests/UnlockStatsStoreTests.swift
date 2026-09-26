import XCTest
@testable import MindRestore

final class UnlockStatsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()
    // Thursday 2026-09-24 12:00 UTC
    private var clock = Date(timeIntervalSince1970: 1_790_251_200)

    override func setUp() {
        defaults = UserDefaults(suiteName: "UnlockStatsStoreTests")!
        defaults.removePersistentDomain(forName: "UnlockStatsStoreTests")
    }

    private func makeStore() -> UnlockStatsStore {
        UnlockStatsStore(defaults: defaults, now: { [unowned self] in self.clock }, calendar: calendar)
    }

    func testRecordsAddUpAcrossTheWeek() {
        let store = makeStore()
        store.recordEarned(minutes: 5)
        store.recordEarned(minutes: 12)
        store.recordDenied()
        store.recordResisted()
        clock += 24 * 3600 // Friday
        store.recordEarned(minutes: 10)
        store.recordResisted()

        XCTAssertEqual(makeStore().thisWeek(), UnlockWeekStats(earned: 3, earnedMinutes: 27, denied: 1, resisted: 2),
                       "survives a new store instance")
    }

    func testWeekStartsFresh() {
        let store = makeStore()
        store.recordEarned(minutes: 15)
        store.recordResisted()
        clock += 4 * 24 * 3600 // Monday of the next week
        XCTAssertEqual(store.thisWeek(), UnlockWeekStats())
        store.recordDenied()
        XCTAssertEqual(store.thisWeek(), UnlockWeekStats(denied: 1))
    }

    func testOldDaysArePruned() {
        let store = makeStore()
        store.recordEarned(minutes: 5)
        clock += 20 * 24 * 3600
        store.recordDenied()
        let stored = defaults.dictionary(forKey: UnlockStatsStore.key) ?? [:]
        XCTAssertEqual(stored.count, 1, "only the last 14 days are kept")
    }
}
