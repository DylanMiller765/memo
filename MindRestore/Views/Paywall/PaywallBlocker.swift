import PostHog
import SwiftUI

// "What stopped you?" (2.1.10). Every real annual-trial checkout from 9/26 to 10/2 ended
// on Apple's sheet, and 7 of 8 guided-arm answers were under 18. One question after a
// no-purchase exit tells marketing whether people can't pay or won't.

enum PaywallBlocker: String, CaseIterable, Identifiable {
    case cantPay = "cant_pay"
    case tooExpensive = "too_expensive"
    case didntExpect = "didnt_expect_to_pay"
    case justLooking = "just_looking"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cantPay: "I can't pay (no card / under 18)"
        case .tooExpensive: "Too expensive"
        case .didntExpect: "Didn't expect to pay"
        case .justLooking: "Just looking"
        case .other: "Something else"
        }
    }
}

enum PaywallBlockerPrompt {
    static let askedKey = "paywall.blockerAsked"

    enum Moment: Equatable {
        /// "No thanks" on the one-time offer.
        case offerDeclined
        /// Backed out of Apple's sheet. When the one-time offer showed, it gets this moment instead.
        case purchaseCancelled(offerShown: Bool)
    }

    static func shouldAsk(_ moment: Moment, alreadyAsked: Bool, isPro: Bool) -> Bool {
        guard !alreadyAsked, !isPro else { return false }
        if case .purchaseCancelled(let offerShown) = moment { return !offerShown }
        return true
    }

    static func properties(reason: String, ageBand: String?, plan: String, trigger: String, route: String?) -> [String: Any] {
        ["reason": reason, "age_band": ageBand ?? "unknown", "plan": plan, "trigger": trigger, "onboarding_route": route ?? "unknown"]
    }

    static func record(_ reason: String, plan: String, trigger: String, defaults: UserDefaults = .standard) {
        let props = properties(reason: reason, ageBand: OnboardingAgeTracking.saved(defaults: defaults), plan: plan, trigger: trigger,
                               route: defaults.string(forKey: OnboardingRouteAssignment.savedKey))
        PostHogSDK.shared.capture("paywall.blocker_answered", properties: props)
        if reason != "dismissed" {
            PostHogSDK.shared.capture("$set", userProperties: ["paywall_blocker": reason])
        }
        // They're usually on their way out: send it now, not on a next launch that may never come.
        PostHogSDK.shared.flush()
    }
}

/// The onboarding age answer, on every later event (super property) and on the person.
enum OnboardingAgeTracking {
    static let savedKey = "onboarding.ageBand"
    static let property = "age_band"

    static func value(for band: GuidedAgeBand?) -> String { band?.rawValue ?? "skipped" }

    static func saved(defaults: UserDefaults = .standard) -> String? { defaults.string(forKey: savedKey) }

    static func save(_ band: GuidedAgeBand?, defaults: UserDefaults = .standard) {
        defaults.set(value(for: band), forKey: savedKey)
    }

    static func record(_ band: GuidedAgeBand?) {
        save(band)
        let value = value(for: band)
        PostHogSDK.shared.register([property: value])
        PostHogSDK.shared.capture("$set", userProperties: [property: value])
    }
}

/// One tap and it closes. Calm, no guilt: it's a question, not a second paywall.
struct PaywallBlockerSheet: View {
    let onAnswer: (PaywallBlocker?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick question: what stopped you?")
                .font(.brand(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("One tap. It helps us make Memo work for more people.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 6)
            ForEach(PaywallBlocker.allCases) { blocker in
                Button {
                    HapticService.tap()
                    onAnswer(blocker)
                } label: {
                    Text(blocker.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button("Not now") { onAnswer(nil) }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .preferredColorScheme(.dark)
    }
}
