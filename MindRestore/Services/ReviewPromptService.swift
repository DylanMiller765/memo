import StoreKit
import UIKit

enum ReviewPromptService {
    /// Set when a game qualifies; shown once the player leaves the result screen.
    @MainActor private static var isPending = false

    /// Called as each game is saved. The rating sheet would cover the result
    /// the player just earned, so it waits for `presentPendingIfAny()`.
    @MainActor
    static func requestIfAppropriate(totalExercises: Int, streak: Int) {
        let lastPrompt = UserDefaults.standard.double(forKey: "lastReviewPromptDate")
        let daysSincePrompt = (Date.now.timeIntervalSince1970 - lastPrompt) / 86400
        guard totalExercises >= 5, streak >= 2, daysSincePrompt > 90 else { return }
        isPending = true
    }

    /// Called when the player taps Done on a result: asks for the rating on the way out.
    @MainActor
    static func presentPendingIfAny() {
        guard isPending else { return }
        isPending = false
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastReviewPromptDate")
        // Let the result finish closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)
            }
        }
    }

    /// Prompt for a star rating after a successful first-time paywall purchase.
    /// Skips the engagement gates (exercises/streak) — the user just paid, that
    /// IS the positive interaction. Still respects the 90-day cooldown shared
    /// with `requestIfAppropriate` so a user who subscribes, churns, then
    /// re-subscribes within 90 days does not get double-prompted.
    @MainActor
    static func requestForNewSubscriber() {
        let defaults = UserDefaults.standard
        let lastPrompt = defaults.double(forKey: "lastReviewPromptDate")
        let daysSincePrompt = (Date.now.timeIntervalSince1970 - lastPrompt) / 86400
        guard daysSincePrompt > 90 else { return }

        defaults.set(Date.now.timeIntervalSince1970, forKey: "lastReviewPromptDate")

        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }
}
