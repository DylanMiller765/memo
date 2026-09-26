import XCTest
@testable import MindRestore

final class UnlockRulebookTests: XCTestCase {
    func testThresholdsMatchSpec() {
        let expect: [UnlockGame: [Int]] = [
            .visualMemory: [4, 7, 10], .numberMemory: [6, 8, 10], .chimpTest: [5, 8, 11],
            .mathSprint: [8, 14, 20], .colorMatch: [10, 18, 26], .reactionTime: [400, 320, 270],
        ]
        for (game, values) in expect {
            XCTAssertEqual([UnlockTier.pass, .great, .elite].map { UnlockRulebook.threshold($0, for: game) }, values, "\(game)")
        }
    }

    func testTierHigherIsBetter() {
        XCTAssertEqual(UnlockRulebook.tier(for: .visualMemory, score: 3), .none)
        XCTAssertEqual(UnlockRulebook.tier(for: .visualMemory, score: 4), .pass)
        XCTAssertEqual(UnlockRulebook.tier(for: .visualMemory, score: 9), .great)
        XCTAssertEqual(UnlockRulebook.tier(for: .visualMemory, score: 30), .elite)
    }

    func testReactionLowerIsBetterAndExtremes() {
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 401), .none)
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 400), .pass)
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 300), .great)
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 180), .elite)
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 0), .none, "0 ms means no data, never elite")
        XCTAssertEqual(UnlockRulebook.tier(for: .reactionTime, score: 2000), .none)
    }

    func testMinutes() {
        XCTAssertEqual(UnlockRulebook.minutes(for: .none, isPersonalBest: true), 0)
        XCTAssertEqual(UnlockRulebook.minutes(for: .pass, isPersonalBest: false), 5)
        XCTAssertEqual(UnlockRulebook.minutes(for: .great, isPersonalBest: false), 10)
        XCTAssertEqual(UnlockRulebook.minutes(for: .elite, isPersonalBest: true), 17)
    }

    func testPersonalBestDirection() {
        XCTAssertTrue(UnlockRulebook.isPersonalBest(game: .chimpTest, score: 9, previousBest: 8))
        XCTAssertFalse(UnlockRulebook.isPersonalBest(game: .chimpTest, score: 8, previousBest: 8))
        XCTAssertTrue(UnlockRulebook.isPersonalBest(game: .reactionTime, score: 240, previousBest: 260))
        XCTAssertTrue(UnlockRulebook.isPersonalBest(game: .reactionTime, score: 240, previousBest: 0), "no previous best")
        XCTAssertFalse(UnlockRulebook.isPersonalBest(game: .reactionTime, score: 0, previousBest: 260))
    }

    func testDistanceToPass() {
        XCTAssertEqual(UnlockRulebook.distanceToPass(game: .visualMemory, score: 3), 1)
        XCTAssertEqual(UnlockRulebook.distanceToPass(game: .reactionTime, score: 438), 38)
        XCTAssertEqual(UnlockRulebook.distanceToPass(game: .mathSprint, score: 9), 0)
    }

    func testBannerProgress() {
        XCTAssertEqual(UnlockRulebook.bannerProgress(game: .mathSprint, score: 5, roundsPlayed: 0),
                       BannerProgress(filled: 5, total: 8, targetTier: .pass, isMaxed: false))
        XCTAssertEqual(UnlockRulebook.bannerProgress(game: .mathSprint, score: 10, roundsPlayed: 0),
                       BannerProgress(filled: 2, total: 6, targetTier: .great, isMaxed: false))
        XCTAssertEqual(UnlockRulebook.bannerProgress(game: .mathSprint, score: 25, roundsPlayed: 0),
                       BannerProgress(filled: 1, total: 1, targetTier: .elite, isMaxed: true))
        XCTAssertEqual(UnlockRulebook.bannerProgress(game: .reactionTime, score: 0, roundsPlayed: 2),
                       BannerProgress(filled: 2, total: 5, targetTier: .pass, isMaxed: false))
    }

    func testGameMappingRoundTrips() {
        for game in UnlockGame.allCases {
            XCTAssertEqual(UnlockGame(exerciseType: game.exerciseType), game)
        }
        XCTAssertNil(UnlockGame(exerciseType: .dualNBack))
    }

    func testSlotOddsRespectFreePassRule() {
        var rng = SeededGenerator(seed: 42)
        let spins = (0..<12_000).map { _ in SlotOdds.pick(freePassAvailable: true, using: &rng) }
        let freeRate = Double(spins.filter { $0 == .freePass }.count) / Double(spins.count)
        XCTAssertEqual(freeRate, 0.085, accuracy: 0.012)
        for game in UnlockGame.allCases {
            XCTAssertGreaterThan(spins.filter { $0 == .game(game) }.count, 1_600, "\(game) appears")
        }
        var rng2 = SeededGenerator(seed: 1)
        XCTAssertFalse((0..<5_000).contains { _ in SlotOdds.pick(freePassAvailable: false, using: &rng2) == .freePass })
    }
}
