import XCTest
@testable import MindRestore

final class MathSprintEngineTests: XCTestCase {
    private func sample(_ completed: Int, _ n: Int = 400) -> [SprintProblem] {
        var rng = SeededGenerator(seed: UInt64(completed + 7))
        return (0..<n).map { _ in MathSprintEngine.problem(completed: completed, using: &rng) }
    }

    func testAnswersAreNeverNegativeAndDigitsMatch() {
        for c in [0, 5, 8, 13, 16, 22, 30, 45] {
            for p in sample(c) {
                XCTAssertGreaterThanOrEqual(p.answer, 0, p.text)
                XCTAssertEqual(p.digits, String(p.answer).count, p.text)
            }
        }
    }

    func testQualifyingPhaseIsEasy() {
        for p in sample(0) + sample(7) {
            if p.text.contains("×") {
                let parts = p.text.split(separator: "×").map { Int($0.trimmingCharacters(in: .whitespaces))! }
                XCTAssertTrue(parts.allSatisfy { (2...9).contains($0) }, p.text)
            } else {
                XCTAssertLessThanOrEqual(p.answer, 50, p.text)
            }
        }
    }

    func testOvertimeReachesHardProblems() {
        XCTAssertTrue(sample(22).contains { $0.answer >= 100 }, "15×12-class problems appear by 22")
        XCTAssertTrue(sample(30).contains { $0.text.contains("−") && $0.text.contains("×") }, "two-step by 30")
    }
}

