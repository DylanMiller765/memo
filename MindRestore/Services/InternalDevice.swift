import Foundation
import PostHog

/// Test traffic is tagged `$internal_or_test_user` (person property and super property) so
/// PostHog's "Internal / Test users" cohort (id 249228) filters it out: debug builds, the
/// simulator, TestFlight and App Review installs (sandbox receipt), and phones marked by hand
/// in Settings (7 taps on Version). Event names don't change.
enum InternalDevice {
    static let markedKey = "analytics.markedInternal"
    static let property = "$internal_or_test_user"

    static func isInternal(debug: Bool, simulator: Bool, receiptName: String?, marked: Bool) -> Bool {
        debug || simulator || receiptName == "sandboxReceipt" || marked
    }

    static var isMarked: Bool { UserDefaults.standard.bool(forKey: markedKey) }

    static var current: Bool {
        var debug = false
        #if DEBUG
        debug = true
        #endif
        var simulator = false
        #if targetEnvironment(simulator)
        simulator = true
        #endif
        return isInternal(debug: debug, simulator: simulator,
                          receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent, marked: isMarked)
    }

    /// Runs right after PostHog is set up, so every event from a test device carries the flag.
    static func tagIfNeeded() {
        guard current else { return }
        PostHogSDK.shared.register([property: true])
        PostHogSDK.shared.capture("$set", userProperties: [property: true])
    }

    static func setMarked(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: markedKey)
        if current {
            tagIfNeeded()
        } else {
            PostHogSDK.shared.unregister(property)
            PostHogSDK.shared.capture("$set", userProperties: [property: false])
        }
    }
}
