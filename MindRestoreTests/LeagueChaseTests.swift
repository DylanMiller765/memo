import XCTest
@testable import MindRestore

final class LeagueChaseTests: XCTestCase {
    private func e(_ rank: Int, _ name: String, _ score: Int, me: Bool = false) -> LeaderboardEntryData {
        LeaderboardEntryData(rank: rank, username: name, score: score, avatarEmoji: "", level: 1, isCurrentUser: me)
    }

    func testFocusGapIsDurationToPassNextPlayer() {
        let entries = [e(1, "Maya", 614), e(2, "Ava", 548), e(3, "Leo", 487), e(4, "Dylan", 426, me: true)]
        let chase = LeagueChase.make(category: .focusBlocking, entries: entries)
        XCTAssertEqual(chase?.text, "1h 02m to pass Leo")
        XCTAssertEqual(chase?.nextRank, 3)
        XCTAssertEqual(chase?.progress ?? 0, 426.0 / 487.0, accuracy: 0.001)
    }
    func testGameUnitsAndPlurals() {
        let entries = [e(1, "Ava", 12), e(2, "Dylan", 11, me: true)]
        XCTAssertEqual(LeagueChase.make(category: .visualMemory, entries: entries)?.text, "2 levels to pass Ava")
        XCTAssertEqual(LeagueChase.make(category: .streak, entries: [e(1, "Ava", 5), e(2, "Dylan", 5, me: true)])?.text, "1 day to pass Ava")
        XCTAssertEqual(LeagueChase.make(category: .mathSprint, entries: entries)?.text, "2 more to pass Ava")
    }
    func testReactionTimeLowerIsBetter() {
        let entries = [e(1, "Ava", 210), e(2, "Dylan", 240, me: true)]
        let chase = LeagueChase.make(category: .reactionTime, entries: entries)
        XCTAssertEqual(chase?.text, "31 ms faster to pass Ava")
        XCTAssertEqual(chase?.progress ?? 0, 210.0 / 240.0, accuracy: 0.001)
    }
    func testLeaderShowsLead() {
        let chase = LeagueChase.make(category: .focusBlocking, entries: [e(1, "Dylan", 614, me: true), e(2, "Ava", 548)])
        XCTAssertEqual(chase?.text, "1h 06m ahead of Ava")
        XCTAssertEqual(chase?.progress, 1)
        XCTAssertNil(chase?.nextRank)
    }
    func testNoChaseWhenUserMissingOrAlone() {
        XCTAssertNil(LeagueChase.make(category: .focusBlocking, entries: [e(1, "Ava", 10)]))
        XCTAssertEqual(LeagueChase.make(category: .focusBlocking, entries: [e(1, "Dylan", 10, me: true)])?.text, "Holding #1")
    }
}

final class StickerAvatarPaletteTests: XCTestCase {
    func testPodiumColorsAreDistinctEvenWhenNamesCollide() {
        let names = ["Maya", "Ava", "Leo"]
        XCTAssertEqual(Set(StickerAvatar.distinctIndices(for: names)).count, 3)
        XCTAssertEqual(StickerAvatar.distinctIndices(for: names).first, StickerAvatar.paletteIndex(for: "Maya"))
    }
}
