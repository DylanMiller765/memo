import XCTest
@testable import MindRestore

final class ReviewPromptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testAsksFromTheThirdEarnedUnlock() {
        XCTAssertFalse(ReviewPromptService.shouldAskAfterUnlock(unlocksEarned: 2, lastPrompt: 0, now: now))
        XCTAssertTrue(ReviewPromptService.shouldAskAfterUnlock(unlocksEarned: 3, lastPrompt: 0, now: now))
    }

    func testRespectsTheNinetyDayCooldown() {
        let tenDaysAgo = now.addingTimeInterval(-10 * 86400).timeIntervalSince1970
        let hundredDaysAgo = now.addingTimeInterval(-100 * 86400).timeIntervalSince1970
        XCTAssertFalse(ReviewPromptService.shouldAskAfterUnlock(unlocksEarned: 5, lastPrompt: tenDaysAgo, now: now))
        XCTAssertTrue(ReviewPromptService.shouldAskAfterUnlock(unlocksEarned: 5, lastPrompt: hundredDaysAgo, now: now))
    }
}
