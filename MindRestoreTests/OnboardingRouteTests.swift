import XCTest
@testable import MindRestore

final class OnboardingRouteTests: XCTestCase {
    func testAnInstallKeepsTheRouteItWasGiven() {
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: "guided", remote: "concise", coin: true), "guided")
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: "concise", remote: nil, coin: false), "concise")
    }

    func testPostHogCanSendNewInstallsToOneRoute() {
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: nil, remote: "guided", coin: true), "guided")
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: nil, remote: "concise", coin: false), "concise")
    }

    func testNewInstallsSplitOnTheCoin() {
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: nil, remote: nil, coin: true), "concise")
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: nil, remote: nil, coin: false), "guided")
    }

    func testUnknownValuesAreIgnored() {
        XCTAssertEqual(OnboardingRouteAssignment.pick(saved: "control", remote: "banana", coin: false), "guided")
    }
}
