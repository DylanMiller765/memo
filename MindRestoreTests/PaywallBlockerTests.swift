import XCTest
@testable import MindRestore

final class PaywallBlockerTests: XCTestCase {
    func testDecliningTheOfferAsksOnce() {
        XCTAssertTrue(PaywallBlockerPrompt.shouldAsk(.offerDeclined, alreadyAsked: false, isPro: false))
        XCTAssertFalse(PaywallBlockerPrompt.shouldAsk(.offerDeclined, alreadyAsked: true, isPro: false))
        XCTAssertFalse(PaywallBlockerPrompt.shouldAsk(.offerDeclined, alreadyAsked: false, isPro: true))
    }

    func testACancelledSheetAsksOnlyWhenTheOfferCouldNotShow() {
        XCTAssertFalse(PaywallBlockerPrompt.shouldAsk(.purchaseCancelled(offerShown: true), alreadyAsked: false, isPro: false),
                       "the one-time offer gets that moment; the question comes if they decline it")
        XCTAssertTrue(PaywallBlockerPrompt.shouldAsk(.purchaseCancelled(offerShown: false), alreadyAsked: false, isPro: false))
        XCTAssertFalse(PaywallBlockerPrompt.shouldAsk(.purchaseCancelled(offerShown: false), alreadyAsked: true, isPro: false))
    }

    func testAnswersAndTheirAnalyticsValues() {
        XCTAssertEqual(PaywallBlocker.allCases.map(\.title), [
            "I can't pay (no card / under 18)", "Too expensive", "Didn't expect to pay", "Just looking", "Something else",
        ])
        XCTAssertEqual(PaywallBlocker.allCases.map(\.rawValue), ["cant_pay", "too_expensive", "didnt_expect_to_pay", "just_looking", "other"])
    }

    func testEventPropertiesCarryTheContextMarketingBreaksDownBy() {
        let props = PaywallBlockerPrompt.properties(reason: PaywallBlocker.cantPay.rawValue, ageBand: "under18", plan: "annual",
                                                    trigger: "onboarding_concise", route: "concise")
        XCTAssertEqual(props["reason"] as? String, "cant_pay")
        XCTAssertEqual(props["age_band"] as? String, "under18")
        XCTAssertEqual(props["plan"] as? String, "annual")
        XCTAssertEqual(props["trigger"] as? String, "onboarding_concise")
        XCTAssertEqual(props["onboarding_route"] as? String, "concise")
        let unknown = PaywallBlockerPrompt.properties(reason: "dismissed", ageBand: nil, plan: "weekly", trigger: "settings", route: nil)
        XCTAssertEqual(unknown["age_band"] as? String, "unknown")
        XCTAssertEqual(unknown["onboarding_route"] as? String, "unknown")
    }

    func testAgeBandValues() {
        XCTAssertEqual(OnboardingAgeTracking.value(for: .under18), "under18")
        XCTAssertEqual(OnboardingAgeTracking.value(for: nil), "skipped")
        let d = UserDefaults(suiteName: "PaywallBlockerTests.\(UUID().uuidString)")!
        XCTAssertNil(OnboardingAgeTracking.saved(defaults: d))
        OnboardingAgeTracking.save(.from18, defaults: d)
        XCTAssertEqual(OnboardingAgeTracking.saved(defaults: d), "from18")
        OnboardingAgeTracking.save(nil, defaults: d)
        XCTAssertEqual(OnboardingAgeTracking.saved(defaults: d), "skipped")
    }
}
