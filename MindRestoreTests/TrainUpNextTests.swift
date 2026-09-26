import XCTest
@testable import MindRestore

final class TrainUpNextTests: XCTestCase {
    private let games: [ExerciseType] = [.visualMemory, .sequentialMemory, .chimpTest, .mathSpeed]
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testFirstGameNotPlayedTodayInCatalogOrder() {
        let pick = TrainUpNext.pick(games: games, playedToday: [.visualMemory], lastPlayed: [.visualMemory: now])
        XCTAssertEqual(pick, .sequentialMemory)
    }
    func testNothingPlayedPicksTheFirstGame() {
        XCTAssertEqual(TrainUpNext.pick(games: games, playedToday: [], lastPlayed: [:]), .visualMemory)
    }
    func testAllPlayedTodayPicksLeastRecentlyPlayed() {
        let last: [ExerciseType: Date] = [
            .visualMemory: now, .sequentialMemory: now.addingTimeInterval(-60),
            .chimpTest: now.addingTimeInterval(-3600), .mathSpeed: now.addingTimeInterval(-120),
        ]
        XCTAssertEqual(TrainUpNext.pick(games: games, playedToday: Set(games), lastPlayed: last), .chimpTest)
    }
}
