import XCTest
@testable import MindRestore

final class TimeBankTests: XCTestCase {
    func testStartsAtTenAndDrains() {
        var bank = TimeBank()
        XCTAssertEqual(bank.remaining, 10)
        bank.elapse(4)
        XCTAssertEqual(bank.remaining, 6, accuracy: 0.0001)
        bank.elapse(100)
        XCTAssertEqual(bank.remaining, 0)
        XCTAssertTrue(bank.isEmpty)
    }

    func testBonusShrinksLinearlyToOne() {
        XCTAssertEqual(TimeBank.bonus(afterCompleted: 0), 2.0, accuracy: 0.0001)
        XCTAssertEqual(TimeBank.bonus(afterCompleted: 15), 1.5, accuracy: 0.0001)
        XCTAssertEqual(TimeBank.bonus(afterCompleted: 30), 1.0, accuracy: 0.0001)
        XCTAssertEqual(TimeBank.bonus(afterCompleted: 90), 1.0, accuracy: 0.0001)
    }

    func testCorrectAddsBonusAndCountsCompleted() {
        var bank = TimeBank()
        bank.elapse(5)
        XCTAssertEqual(bank.correct(), 2.0, accuracy: 0.0001)
        XCTAssertEqual(bank.remaining, 7, accuracy: 0.0001)
        XCTAssertEqual(bank.completed, 1)
    }

    func testWrongCostsThreeNeverBelowZero() {
        var bank = TimeBank()
        bank.elapse(8.5)
        bank.wrong()
        XCTAssertEqual(bank.remaining, 0)
        XCTAssertEqual(bank.completed, 0)
    }

    func testCapPreventsBanking() {
        var bank = TimeBank()
        for _ in 0..<10 { bank.correct() }
        XCTAssertEqual(bank.remaining, TimeBank.cap)
    }

    func testNoBonusOnceEmpty() {
        var bank = TimeBank()
        bank.elapse(10)
        XCTAssertEqual(bank.correct(), 0)
        XCTAssertEqual(bank.completed, 0, "a tap after time-out never counts")
    }
}
