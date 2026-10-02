import Foundation

/// Rules for onboarding's Chimp Test demo. Real users spent 1–2.5 minutes on
/// the uncapped demo and 2 of 7 quit inside it (week to Oct 1, 2026), so the
/// demo now ends as a win once the player remembers `levelCap` numbers.
enum OnboardingDemoRun {
    static let levelCap = 5

    static func reachedCap(_ levelsCleared: Int) -> Bool { levelsCleared >= levelCap }

    /// Honest about the run: the first ticket pays out either way.
    static func payoutIntro(levelsCleared: Int) -> String {
        reachedCap(levelsCleared)
            ? "Warm-up cleared. Your ticket pays out."
            : "Nice try. Memo pays out anyway on your first run."
    }

    static func rankFootnote(levelsCleared: Int) -> String? {
        if reachedCap(levelsCleared) { return "Warm-up done. Chimps average 7." }
        return levelsCleared > 0 ? "Chimps average 7. You remembered \(levelsCleared)." : nil
    }
}

/// Why the one-time offer can't show. `alreadySeen` and `alreadyPro` are by
/// design; the other two mean someone should have seen it and didn't.
enum ExitOfferGate {
    enum Blocker: String, Equatable {
        case alreadySeen = "already_seen"
        case alreadyPro = "already_pro"
        case productMissing = "product_missing"
        case noDiscount = "no_discount"

        var isUnexpected: Bool { self == .productMissing || self == .noDiscount }
    }

    static func blocker(seen: Bool, isPro: Bool, hasProduct: Bool, discountPercent: Int) -> Blocker? {
        if seen { return .alreadySeen }
        if isPro { return .alreadyPro }
        if !hasProduct { return .productMissing }
        if discountPercent <= 0 { return .noDiscount }
        return nil
    }
}
