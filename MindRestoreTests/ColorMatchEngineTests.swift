import XCTest
@testable import MindRestore

final class ColorMatchEngineTests: XCTestCase {
    func testQualifyUsesFourColorsOvertimeAddsPurple() {
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<200 {
            let p = ColorMatchEngine.prompt(completed: 3, previous: nil, using: &rng)
            XCTAssertEqual(p.choices.count, 4)
            XCTAssertFalse(p.choices.contains(.purple))
            XCTAssertTrue(p.choices.contains(p.ink))
        }
        let late = ColorMatchEngine.prompt(completed: 12, previous: nil, using: &rng)
        XCTAssertEqual(late.choices.count, 5)
    }

    func testMostlyIncongruentAndNeverRepeatsExactly() {
        var rng = SeededGenerator(seed: 9)
        var prev: StroopPrompt?
        var incongruent = 0
        for _ in 0..<300 {
            let p = ColorMatchEngine.prompt(completed: 15, previous: prev, using: &rng)
            if p.word != p.ink { incongruent += 1 }
            XCTAssertNotEqual(p, prev)
            prev = p
        }
        XCTAssertGreaterThan(incongruent, 240)
    }
}
