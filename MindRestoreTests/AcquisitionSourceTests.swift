import XCTest
@testable import MindRestore

final class AcquisitionSourceTests: XCTestCase {
    func testOptionsAppearInTheOrderAskedWithStableAnalyticsValues() {
        XCTAssertEqual(
            AcquisitionSource.allCases.map(\.rawValue),
            ["tiktok", "instagram", "youtube", "app_store_search", "friend", "other"]
        )
        XCTAssertEqual(
            AcquisitionSource.allCases.map(\.title),
            ["TikTok", "Instagram", "YouTube", "App Store search", "A friend", "Other"]
        )
    }

    func testAnswerIsSentAsTheSourceProperty() {
        let properties = Analytics.attributionSelectedProperties(source: .youtube)
        XCTAssertEqual(properties["source"] as? String, "youtube")
    }

    func testSkipIsRecordedAsSkipped() {
        let properties = Analytics.attributionSelectedProperties(source: nil)
        XCTAssertEqual(properties["source"] as? String, "skipped")
    }
}
