import XCTest
@testable import MindRestore

/// The weekly board every game end shows: right game name, right ranking direction.
final class GameEndDataTests: XCTestCase {
    func testReactionRivalsAreLowerIsBetter() {
        let rivals = OnboardingRivals.entries(level: 250, lowerIsBetter: true)
        XCTAssertEqual(rivals.first?.username, "Byte")
        XCTAssertLessThan(rivals.first!.score, 250, "Byte leads with a faster (lower) time")
        XCTAssertGreaterThan(rivals.last!.score, 250)
    }

    func testBoardUnitNamesTheGame() {
        XCTAssertEqual(BoardUnit.forGame(.mathSprint).gameName, "Math Sprint")
        XCTAssertEqual(BoardUnit.forGame(.reactionTime).next(after: 212), 211)
        XCTAssertEqual(BoardUnit.forGame(.visualMemory).next(after: 9), 10)
    }

    func testResultScoreLineReadsInTheGamesUnit() {
        XCTAssertEqual(BoardUnit.forGame(.visualMemory).capitalized(9), "Level 9")
        XCTAssertEqual(BoardUnit.forGame(.numberMemory).capitalized(9), "9 digits")
        XCTAssertEqual(BoardUnit.forGame(.reactionTime).short(250), "250 ms")
    }
}
