import XCTest
@testable import MindRestore

@MainActor
final class OnboardingDemoTests: XCTestCase {
    // MARK: Level cap (b)

    func testTheDemoEndsAsAWinAtFiveNumbers() {
        XCTAssertEqual(OnboardingDemoRun.levelCap, 5)
        XCTAssertFalse(OnboardingDemoRun.reachedCap(4))
        XCTAssertTrue(OnboardingDemoRun.reachedCap(5))
    }

    func testACappedRunReadsAsAWin() {
        XCTAssertEqual(OnboardingDemoRun.payoutIntro(levelsCleared: 5), "Warm-up cleared. Your ticket pays out.")
        XCTAssertEqual(OnboardingDemoRun.rankFootnote(levelsCleared: 5), "Warm-up done. Chimps average 7.")
    }

    func testAMissBeforeTheCapKeepsTheFirstRunPromise() {
        XCTAssertEqual(OnboardingDemoRun.payoutIntro(levelsCleared: 4), "Nice try. Memo pays out anyway on your first run.")
        XCTAssertEqual(OnboardingDemoRun.rankFootnote(levelsCleared: 4), "Chimps average 7. You remembered 4.")
        XCTAssertNil(OnboardingDemoRun.rankFootnote(levelsCleared: 0))
    }

    func testThePreviewGameFinishesWhenItReachesTheCap() {
        let game = ChimpTestViewModel()
        game.isOnboardingPreview = true
        game.previewLevelCap = 5
        game.startGame()
        clearLevel(game)                       // 4 numbers
        waitForNextLevel(game, numbers: 5)
        clearLevel(game)                       // 5 numbers: the cap
        let finished = expectation(description: "finished at the cap")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(game.phase, .finished)
            XCTAssertEqual(game.bestLevel, 5)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
    }

    func testTheRealGameIsNotCapped() {
        let game = ChimpTestViewModel()
        game.startGame()
        clearLevel(game)
        waitForNextLevel(game, numbers: 5)
        clearLevel(game)
        let next = expectation(description: "keeps going")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(game.phase, .playing)
            XCTAssertEqual(game.currentLevel, 6)
            next.fulfill()
        }
        wait(for: [next], timeout: 2)
    }

    // MARK: Demo analytics (a)

    func testStageViewedProperties() {
        let props = Analytics.demoStageViewedProperties(stage: "game", secondsSinceDemoStart: 7.6, run: 1)
        XCTAssertEqual(props["stage"] as? String, "game")
        XCTAssertEqual(props["seconds_since_demo_start"] as? Int, 8)
        XCTAssertEqual(props["run"] as? Int, 1)
    }

    func testGameEndedPropertiesSayHowTheRunEnded() {
        let capped = Analytics.demoGameEndedProperties(levelsCleared: 5, secondsInGame: 21.2, run: 1)
        XCTAssertEqual(capped["levels_cleared"] as? Int, 5)
        XCTAssertEqual(capped["seconds_in_game"] as? Int, 21)
        XCTAssertEqual(capped["ended_by"] as? String, "cap")
        XCTAssertEqual(Analytics.demoGameEndedProperties(levelsCleared: 4, secondsInGame: 9, run: 2)["ended_by"] as? String, "miss")
    }

    // MARK: One-time offer gate (d)

    func testTheOfferShowsForAnUnseenFreeUserWithTheProductLoaded() {
        XCTAssertNil(ExitOfferGate.blocker(seen: false, isPro: false, hasProduct: true, discountPercent: 25))
    }

    func testExpectedBlockersAreNotProblems() {
        XCTAssertEqual(ExitOfferGate.blocker(seen: true, isPro: false, hasProduct: true, discountPercent: 25), .alreadySeen)
        XCTAssertEqual(ExitOfferGate.blocker(seen: false, isPro: true, hasProduct: true, discountPercent: 25), .alreadyPro)
        XCTAssertFalse(ExitOfferGate.Blocker.alreadySeen.isUnexpected)
        XCTAssertFalse(ExitOfferGate.Blocker.alreadyPro.isUnexpected)
    }

    func testAMissingProductOrDiscountIsReported() {
        XCTAssertEqual(ExitOfferGate.blocker(seen: false, isPro: false, hasProduct: false, discountPercent: 25), .productMissing)
        XCTAssertEqual(ExitOfferGate.blocker(seen: false, isPro: false, hasProduct: true, discountPercent: 0), .noDiscount)
        XCTAssertTrue(ExitOfferGate.Blocker.productMissing.isUnexpected)
        XCTAssertEqual(ExitOfferGate.Blocker.productMissing.rawValue, "product_missing")
        XCTAssertEqual(ExitOfferGate.Blocker.noDiscount.rawValue, "no_discount")
    }

    // MARK: Helpers

    private func clearLevel(_ game: ChimpTestViewModel) {
        for number in 1...game.currentLevel {
            guard let index = game.grid.firstIndex(of: number) else { return XCTFail("missing \(number)") }
            game.tapCell(at: index)
        }
    }

    private func waitForNextLevel(_ game: ChimpTestViewModel, numbers: Int) {
        let ready = expectation(description: "level \(numbers)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(game.currentLevel, numbers)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 2)
    }
}
