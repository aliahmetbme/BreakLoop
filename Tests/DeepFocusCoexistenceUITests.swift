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
    func testMonitoringOffersOneContextRowBelowExplanationAndOpensSheet() throws {
        let app = launch("active")
        let focus = app.buttons["dashboard.deepFocusContextAction"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8), app.debugDescription)
        let title = app.staticTexts["Your cycle is running."]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThan(focus.frame.minY, title.frame.maxY)
        XCTAssertEqual(app.buttons.matching(identifier: "dashboard.deepFocusContextAction").count, 1)
        for _ in 0..<6 where !focus.isHittable { app.swipeUp() }
        XCTAssertTrue(focus.isHittable)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
        XCTAssertEqual(focus.value as? String, "Your Usage Cycle keeps running.")
        XCTAssertTrue(app.buttons["Stop Usage Cycle"].exists)
        focus.tap()
        XCTAssertTrue(app.navigationBars["Deep Focus Setup"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
    }
    func testMonitoringTurkishAccessibilityTextStillOffersFocus() throws {
        let app = launch("active", turkish: true, large: true)
        let focus = app.buttons["dashboard.deepFocusContextAction"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8), app.debugDescription)
        for _ in 0..<6 where !focus.isHittable { app.swipeUp() }
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
