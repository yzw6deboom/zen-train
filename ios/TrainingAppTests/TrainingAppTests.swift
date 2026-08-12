import XCTest
@testable import TrainingApp

/// 验证应用最小工程中的可观察行为。
final class TrainingAppTests: XCTestCase {
    /// 正式环境应向根视图提供正确的产品名称。
    func testLiveEnvironmentUsesTheProductDisplayName() {
        XCTAssertEqual(AppEnvironment.live.displayName, "ZenTrain")
    }
}
