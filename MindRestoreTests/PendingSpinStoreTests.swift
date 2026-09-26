import XCTest
@testable import MindRestore

final class PendingSpinStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "PendingSpinStoreTests")!
        defaults.removePersistentDomain(forName: "PendingSpinStoreTests")
    }

    private func makeStore() -> PendingSpinStore {
        PendingSpinStore(defaults: defaults, now: { [unowned self] in self.clock })
    }

    func testBeginPersistsAndNoReroll() {
        let store = makeStore()
        let first = store.begin(.chimpTest)
        let second = store.begin(.mathSprint)
        XCTAssertEqual(second.game, .chimpTest, "reopening the slot returns the same spin")
        XCTAssertEqual(makeStore().current(), first, "survives a new store instance (app relaunch / second shield tap)")
    }

    func testExpiresAfterThirtyMinutes() {
        let store = makeStore()
        store.begin(.visualMemory)
        clock += 29 * 60
        XCTAssertNotNil(store.current())
        clock += 61
        XCTAssertNil(store.current())
        XCTAssertEqual(store.begin(.colorMatch).game, .colorMatch)
    }

    func testDenialsCountOnTheSameSpin() {
        let store = makeStore()
        XCTAssertEqual(store.recordDenial(), 0, "no spin, no count")
        store.begin(.numberMemory)
        XCTAssertEqual(store.recordDenial(), 1)
        XCTAssertEqual(store.recordDenial(), 2)
        store.resolve()
        XCTAssertNil(store.current())
    }

    func testFreePassOncePerCalendarDay() {
        let store = makeStore()
        XCTAssertTrue(store.freePassAvailableToday)
        store.markFreePassUsed()
        XCTAssertFalse(store.freePassAvailableToday)
        clock += 60 * 60 * 24
        XCTAssertTrue(store.freePassAvailableToday)
    }
}
