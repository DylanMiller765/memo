import Foundation

struct SprintProblem: Equatable {
    let text: String
    let answer: Int
    var digits: Int { String(answer).count }
}

enum MathSprintEngine {
    static let qualifyCount = 8

    static func problem<R: RandomNumberGenerator>(completed: Int, using rng: inout R) -> SprintProblem {
        switch completed {
        case ..<qualifyCount:
            if Bool.random(using: &rng) {
                let a = Int.random(in: 2...9, using: &rng), b = Int.random(in: 2...9, using: &rng)
                return SprintProblem(text: "\(a) × \(b)", answer: a * b)
            }
            if Bool.random(using: &rng) {
                let a = Int.random(in: 5...30, using: &rng), b = Int.random(in: 2...(50 - a), using: &rng)
                return SprintProblem(text: "\(a) + \(b)", answer: a + b)
            }
            let a = Int.random(in: 10...50, using: &rng), b = Int.random(in: 2...a, using: &rng)
            return SprintProblem(text: "\(a) − \(b)", answer: a - b)
        case ..<14:
            let a = Int.random(in: 3...12, using: &rng), b = Int.random(in: 6...12, using: &rng)
            return SprintProblem(text: "\(a) × \(b)", answer: a * b)
        case ..<20:
            let a = Int.random(in: 11...19, using: &rng), b = Int.random(in: 3...9, using: &rng)
            return SprintProblem(text: "\(a) × \(b)", answer: a * b)
        case ..<28:
            let a = Int.random(in: 11...19, using: &rng), b = Int.random(in: 11...15, using: &rng)
            return SprintProblem(text: "\(a) × \(b)", answer: a * b)
        default:
            if Int.random(in: 0..<3, using: &rng) == 0 {
                let a = Int.random(in: 12...19, using: &rng), b = Int.random(in: 11...19, using: &rng)
                return SprintProblem(text: "\(a) × \(b)", answer: a * b)
            }
            let a = Int.random(in: 4...12, using: &rng), b = Int.random(in: 4...12, using: &rng)
            let c = Int.random(in: 2...min(30, a * b), using: &rng)
            return SprintProblem(text: "\(a) × \(b) − \(c)", answer: a * b - c)
        }
    }
}
