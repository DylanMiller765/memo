import XCTest
@testable import MindRestore

final class InternalDeviceTests: XCTestCase {
    func testDebugSimulatorAndSandboxBuildsAreTestDevices() {
        XCTAssertTrue(InternalDevice.isInternal(debug: true, simulator: false, receiptName: "receipt", marked: false))
        XCTAssertTrue(InternalDevice.isInternal(debug: false, simulator: true, receiptName: "receipt", marked: false))
        // TestFlight and App Review installs carry a sandbox receipt.
        XCTAssertTrue(InternalDevice.isInternal(debug: false, simulator: false, receiptName: "sandboxReceipt", marked: false))
    }

    func testAMarkedPhoneIsInternal() {
        XCTAssertTrue(InternalDevice.isInternal(debug: false, simulator: false, receiptName: "receipt", marked: true))
    }

    func testAnAppStoreInstallIsARealUser() {
        XCTAssertFalse(InternalDevice.isInternal(debug: false, simulator: false, receiptName: "receipt", marked: false))
        XCTAssertFalse(InternalDevice.isInternal(debug: false, simulator: false, receiptName: nil, marked: false))
    }
}
