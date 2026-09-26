import Foundation

struct PendingSpin: Codable, Equatable {
    let game: UnlockGame
    let createdAt: Date
    var denials: Int
}

final class PendingSpinStore {
    static let shared = PendingSpinStore(defaults: UserDefaults(suiteName: "group.com.memori.shared") ?? .standard)

    private enum Key {
        static let spin = "unlock_pending_spin"
        static let freePassDay = "unlock_free_pass_day"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
    }

    func current() -> PendingSpin? {
        guard let data = defaults.data(forKey: Key.spin),
              let spin = try? JSONDecoder().decode(PendingSpin.self, from: data) else { return nil }
        if now().timeIntervalSince(spin.createdAt) > UnlockRulebook.pendingSpinLifetime {
            resolve()
            return nil
        }
        return spin
    }

    @discardableResult
    func begin(_ game: UnlockGame) -> PendingSpin {
        if let existing = current() { return existing }
        let spin = PendingSpin(game: game, createdAt: now(), denials: 0)
        save(spin)
        return spin
    }

    @discardableResult
    func recordDenial() -> Int {
        guard var spin = current() else { return 0 }
        spin.denials += 1
        save(spin)
        return spin.denials
    }

    func resolve() {
        defaults.removeObject(forKey: Key.spin)
    }

    var freePassAvailableToday: Bool {
        defaults.string(forKey: Key.freePassDay) != dayStamp()
    }

    func markFreePassUsed() {
        defaults.set(dayStamp(), forKey: Key.freePassDay)
    }

    private func save(_ spin: PendingSpin) {
        if let data = try? JSONEncoder().encode(spin) { defaults.set(data, forKey: Key.spin) }
    }

    private func dayStamp() -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}
