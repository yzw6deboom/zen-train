import XCTest

final class TrainingAppUITests: XCTestCase {
    func testAppLaunchesIntoTheCompositionRoot() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertTrue(
            app.staticTexts["app-root-title"].waitForExistence(timeout: 5),
            "The Composition Root should present the app's root view."
        )
    }
}
