import XCTest
@testable import MindRestore

final class CatalogTests: XCTestCase {
    func testActiveGamesAreExactlyTheSix() {
        XCTAssertEqual(Set(ExerciseType.activeGames),
                       [.visualMemory, .sequentialMemory, .chimpTest, .mathSpeed, .colorMatch, .reactionTime])
        XCTAssertTrue(ExerciseType.allCases.filter { !$0.isRetired }.allSatisfy(ExerciseType.activeGames.contains))
    }

    func testUnlockCatalogHasNoRetiredGames() {
        let types = TrainingGameCatalog.focusUnlockGames.map(\.type)
        XCTAssertEqual(types.count, 6)
        XCTAssertFalse(types.contains(where: \.isRetired))
        XCTAssertEqual(TrainingGameCatalog.focusUnlockGames.first(where: { $0.type == .mathSpeed })?.title, "Math Sprint")
    }
}
