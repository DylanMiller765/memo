import Foundation
import PostHog

/// Which onboarding a new install gets in the onboarding test: today's short route
/// ("concise") or the guided one. Each install flips a coin once and keeps the answer,
/// so a late-loading PostHog flag can't split someone's onboarding. The `onboarding-route`
/// flag, when set, sends new installs to one route (to roll out the winner without a release).
enum OnboardingRouteAssignment {
    static let routes: Set<String> = ["concise", "guided"]
    static let savedKey = "onboarding.route"

    static func pick(saved: String?, remote: String?, coin: Bool) -> String {
        if let saved, routes.contains(saved) { return saved }
        if let remote, routes.contains(remote) { return remote }
        return coin ? "concise" : "guided"
    }

    /// Resolves and remembers this install's route, and tags every PostHog event with it.
    static func current(defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: savedKey)
        let route = pick(saved: saved, remote: PostHogSDK.shared.getFeatureFlag("onboarding-route") as? String, coin: Bool.random())
        if saved != route {
            defaults.set(route, forKey: savedKey)
        }
        PostHogSDK.shared.register(["onboarding_route": route])
        return route
    }
}
