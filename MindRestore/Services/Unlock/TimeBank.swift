import Foundation

struct TimeBank: Equatable {
    static let start: Double = 10
    static let penalty: Double = 3
    static let cap: Double = 15

    private(set) var remaining: Double = TimeBank.start
    private(set) var completed: Int = 0

    var isEmpty: Bool { remaining <= 0 }
    var fraction: Double { min(1, max(0, remaining / Self.cap)) }

    static func bonus(afterCompleted completed: Int) -> Double {
        max(1.0, 2.0 - Double(completed) / 30.0)
    }

    mutating func elapse(_ seconds: Double) {
        remaining = max(0, remaining - max(0, seconds))
    }

    @discardableResult
    mutating func correct() -> Double {
        guard !isEmpty else { return 0 }
        let bonus = Self.bonus(afterCompleted: completed)
        completed += 1
        remaining = min(Self.cap, remaining + bonus)
        return bonus
    }

    @discardableResult
    mutating func wrong() -> Double {
        guard !isEmpty else { return 0 }
        remaining = max(0, remaining - Self.penalty)
        return Self.penalty
    }
}
