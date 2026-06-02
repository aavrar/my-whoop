import XCTest
@testable import OpenWhoop

final class SyncStatusNotifierTests: XCTestCase {
    func testBodyAppendsStrainWhenKnown() {
        let body = SyncStatusNotifier.body(at: Date(), strain: 4.94)
        XCTAssertTrue(body.hasPrefix("Last successful sync:"))
        XCTAssertTrue(body.contains("Current Strain: 4.9"), "strain should be appended, 1 decimal: \(body)")
    }

    func testBodyOmitsStrainWhenNil() {
        let body = SyncStatusNotifier.body(at: Date(), strain: nil)
        XCTAssertTrue(body.hasPrefix("Last successful sync:"))
        XCTAssertFalse(body.contains("Strain"))
    }
}
