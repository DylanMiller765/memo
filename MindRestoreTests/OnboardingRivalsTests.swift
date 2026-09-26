import XCTest
@testable import MindRestore

final class OnboardingRivalsTests: XCTestCase {
    func testRivalsSurroundTheDemoLevelSoTheClimbPassesSome() {
        let board = OnboardingRivals.entries(level: 6)
        XCTAssertEqual(board.map(\.username), ["Byte", "Turbo", "Pixel", "Nova"])
        XCTAssertEqual(board.map(\.score), [8, 5, 4, 3])
        XCTAssertEqual(board.map(\.rank), [1, 2, 3, 4])
        XCTAssertTrue(board.allSatisfy(\.isRival))
        XCTAssertFalse(board.contains(where: \.isCurrentUser))
    }

    func testLowLevelsDropRivalsThatWouldScoreZero() {
        let board = OnboardingRivals.entries(level: 2)
        XCTAssertEqual(board.map(\.score), [4, 1])
        XCTAssertTrue(board.allSatisfy { $0.score >= 1 })
    }

    func testSomeoneIsAlwaysAheadToChase() {
        for level in 1...20 {
            let board = OnboardingRivals.entries(level: level)
            XCTAssertGreaterThan(board.first?.score ?? 0, level)
        }
    }

    func testNoLevelMeansNoBoard() {
        XCTAssertTrue(OnboardingRivals.entries(level: 0).isEmpty)
    }
}
