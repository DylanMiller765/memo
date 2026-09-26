import XCTest
@testable import MindRestore

@MainActor
final class UnlockRunTests: XCTestCase {
    func testQualifyingOpensChoiceOnceThenOvertimeBanks() {
        let run = UnlockRun(game: .mathSprint, previousBest: 30)
        run.report(score: 7)
        XCTAssertEqual(run.phase, .playing)
        XCTAssertEqual(run.bankedTier, .none)
        run.report(score: 8)
        XCTAssertEqual(run.phase, .choosing)
        XCTAssertTrue(run.isFrozen, "timer stops while choosing")
        run.keepGoing()
        XCTAssertEqual(run.phase, .overtime)
        run.report(score: 15)
        XCTAssertEqual(run.bankedTier, .great)
        XCTAssertEqual(run.phase, .overtime, "choice only appears once")
        run.finish(finalScore: 16)
        XCTAssertEqual(run.phase, .ended(.unlocked(minutes: 10, tier: .great, score: 16, isPersonalBest: false)))
    }

    func testCashOutPaysPass() {
        let run = UnlockRun(game: .visualMemory, previousBest: 0)
        run.report(score: 4)
        run.cashOut()
        XCTAssertEqual(run.phase, .ended(.unlocked(minutes: 7, tier: .pass, score: 4, isPersonalBest: true)))
    }

    func testFailingBeforePassIsDenied() {
        let run = UnlockRun(game: .chimpTest, previousBest: 9)
        run.report(score: 3)
        run.finish(finalScore: 3)
        XCTAssertEqual(run.phase, .ended(.denied(score: 3, distance: 2)))
    }

    func testAbandonBeforePassDeniesAfterPassCashesOut() {
        let early = UnlockRun(game: .numberMemory, previousBest: 7)
        early.report(score: 4)
        early.abandon()
        XCTAssertEqual(early.phase, .ended(.denied(score: 4, distance: 2)))

        let late = UnlockRun(game: .numberMemory, previousBest: 12)
        late.report(score: 6)
        late.keepGoing()
        late.report(score: 8)
        late.abandon()
        XCTAssertEqual(late.phase, .ended(.unlocked(minutes: 10, tier: .great, score: 8, isPersonalBest: false)))
    }

    func testPauseFreezesWithoutEnding() {
        let run = UnlockRun(game: .colorMatch, previousBest: 0)
        run.setPaused(true)
        XCTAssertTrue(run.isFrozen)
        XCTAssertEqual(run.phase, .playing)
        run.setPaused(false)
        XCTAssertFalse(run.isFrozen)
    }

    func testReactionHasNoChoiceAndUsesAverage() {
        let run = UnlockRun(game: .reactionTime, previousBest: 300)
        run.reportRound(averageMs: 280, roundsPlayed: 3)
        XCTAssertEqual(run.phase, .playing)
        XCTAssertEqual(run.progress, BannerProgress(filled: 3, total: 5, targetTier: .pass, isMaxed: false))
        run.finish(finalScore: 265)
        XCTAssertEqual(run.phase, .ended(.unlocked(minutes: 17, tier: .elite, score: 265, isPersonalBest: true)))

        let slow = UnlockRun(game: .reactionTime, previousBest: 300)
        slow.finish(finalScore: 438)
        XCTAssertEqual(slow.phase, .ended(.denied(score: 438, distance: 38)))
    }

    func testEndedRunIgnoresFurtherInput() {
        let run = UnlockRun(game: .visualMemory, previousBest: 0)
        run.finish(finalScore: 2)
        run.report(score: 9)
        run.cashOut()
        XCTAssertEqual(run.phase, .ended(.denied(score: 2, distance: 2)))
    }
}
