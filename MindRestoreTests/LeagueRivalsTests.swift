import XCTest
@testable import MindRestore

final class LeagueRivalsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func d(_ day: Int, _ hour: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }
    private func e(_ rank: Int, _ name: String, _ score: Int, me: Bool = false) -> LeaderboardEntryData {
        LeaderboardEntryData(rank: rank, username: name, score: score, avatarEmoji: "", level: 1, isCurrentUser: me)
    }

    func testFullBoardGetsNoRivals() {
        let real = (1...5).map { e($0, "P\($0)", 100 - $0) }
        let board = LeagueRivals.board(real: real, category: .chimpTest, baseline: 90, day: d(26), calendar: cal)
        XCTAssertEqual(board.filter(\.isRival).count, 0)
        XCTAssertEqual(board.count, 5)
    }

    func testSparseBoardFillsToFiveWithLabeledRivalsAroundYou() {
        let real = [e(1, "Dylan", 10, me: true)]
        let board = LeagueRivals.board(real: real, category: .chimpTest, baseline: 10, day: d(26), calendar: cal)
        XCTAssertEqual(board.count, 5)
        XCTAssertEqual(board.filter(\.isRival).count, 4)
        XCTAssertEqual(board.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertTrue(board.filter(\.isRival).allSatisfy { LeagueRivals.names.contains($0.username) })
        let me = board.first(where: \.isCurrentUser)!
        // Someone just ahead to chase, someone behind to stay ahead of.
        XCTAssertTrue(board.contains { $0.isRival && $0.rank == me.rank - 1 })
        XCTAssertTrue(board.contains { $0.isRival && $0.rank == me.rank + 1 })
        XCTAssertTrue(board.allSatisfy { $0.score > 0 })
    }

    func testRivalsArePassableOnceYouImproveOnTheDay() {
        // Rivals are paced off the morning baseline (10); scoring 14 later passes the one just ahead.
        let morning = LeagueRivals.board(real: [e(1, "Dylan", 10, me: true)], category: .chimpTest, baseline: 10, day: d(26), calendar: cal)
        let ahead = morning.first { $0.isRival && $0.score > 10 && $0.score < 14 }
        XCTAssertNotNil(ahead)
        let later = LeagueRivals.board(real: [e(1, "Dylan", 14, me: true)], category: .chimpTest, baseline: 10, day: d(26), calendar: cal)
        let meLater = later.first(where: \.isCurrentUser)!
        let aheadLater = later.first { $0.username == ahead!.username }!
        XCTAssertLessThan(meLater.rank, aheadLater.rank)
    }

    func testReactionRivalAheadIsFaster() {
        let board = LeagueRivals.board(real: [e(1, "Dylan", 300, me: true)], category: .reactionTime, baseline: 300, day: d(26), calendar: cal)
        let me = board.first(where: \.isCurrentUser)!
        let justAhead = board.first { $0.rank == me.rank - 1 }!
        XCTAssertTrue(justAhead.isRival)
        XCTAssertLessThan(justAhead.score, 300)
    }

    func testEmptyBoardStillShowsRivalsFromDefaults() {
        let board = LeagueRivals.board(real: [], category: .focusBlocking, baseline: nil, day: d(26), calendar: cal)
        XCTAssertEqual(board.count, 4)
        XCTAssertTrue(board.allSatisfy(\.isRival))
    }

    func testBaselineIsFixedForTheDayAndRepacesTomorrow() {
        let ud = UserDefaults(suiteName: "LeagueRivalsTests")!; ud.removePersistentDomain(forName: "LeagueRivalsTests")
        XCTAssertEqual(LeagueRivalMemory.baseline(category: .chimpTest, filter: .thisWeek, userScore: 10, now: d(26, 9), defaults: ud, calendar: cal), 10)
        XCTAssertEqual(LeagueRivalMemory.baseline(category: .chimpTest, filter: .thisWeek, userScore: 14, now: d(26, 20), defaults: ud, calendar: cal), 10)
        XCTAssertEqual(LeagueRivalMemory.baseline(category: .chimpTest, filter: .thisWeek, userScore: 14, now: d(27, 9), defaults: ud, calendar: cal), 14)
        XCTAssertNil(LeagueRivalMemory.baseline(category: .mathSprint, filter: .thisWeek, userScore: nil, now: d(27, 9), defaults: ud, calendar: cal))
    }
}
