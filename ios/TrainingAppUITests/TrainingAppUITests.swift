import XCTest

/// 从用户视角验证应用能否通过组合根正常启动。
final class TrainingAppUITests: XCTestCase {
    /// 启动应用后，根视图中的产品标题应在五秒内出现。
    @MainActor
    func testAppLaunchesIntoTheCompositionRoot() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertTrue(
            app.staticTexts["app-root-title"].waitForExistence(timeout: 5),
            "组合根应该成功显示应用根视图。"
        )
    }
}
