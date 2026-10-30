// Isolated native UI fixture only; see Docs/Deep-Focus-Coexistence-Report.md.
// Does not prove actual DeviceActivity scheduling or shielding.
import XCTest

@MainActor final class DeepFocusCoexistenceUITests: XCTestCase {
    private func launch(_ runtime: String, turkish: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--selection", "valid", "--runtime", runtime, "--width", "320", "--type", large ? "large" : "default", "--theme", turkish ? "dark" : "light", "-AppleLanguages", turkish ? "(tr)" : "(en)", "-AppleLocale", turkish ? "tr_TR" : "en_US"]
        app.launch()
        return app
    }
    func testMonitoringOffersOneFocusActionAboveRingAndOpensSheet() throws {
        let app = launch("active")
        let focus = app.buttons["Start Deep Focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "Start Deep Focus").count, 1)
        XCTAssertTrue(focus.isHittable)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
        focus.tap()
        XCTAssertTrue(app.navigationBars["Deep Focus Setup"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
    }
    func testMonitoringTurkishAccessibilityTextStillOffersFocus() throws {
        let app = launch("active", turkish: true, large: true)
        let focus = app.buttons["Derin Odağı Başlat"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8))
        XCTAssertTrue(focus.isHittable)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
    }
    func testOverlapExplainsUnderlyingCycleWithoutStartAction() {
        let app = launch("overlap")
        XCTAssertTrue(app.staticTexts["Usage Cycle remains active in the background."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Start Deep Focus"].exists)
    }
    func testIncompatibleRuntimeDoesNotOfferFocus() {
        for runtime in ["cooldown", "loading", "failure"] {
            let app = launch(runtime)
            XCTAssertFalse(app.buttons["Start Deep Focus"].exists, runtime)
            app.terminate()
        }
    }
}
