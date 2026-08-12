import XCTest
@testable import TrainingApp

final class TrainingAppTests: XCTestCase {
    func testLiveEnvironmentUsesTheProductDisplayName() {
        XCTAssertEqual(AppEnvironment.live.displayName, "ZenTrain")
    }
}
