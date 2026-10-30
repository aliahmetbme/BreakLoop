// Run with the isolated UI fixture described in Docs/First-Run-Setup-Report.md.
// Launch arguments below are test-only adapters and are not supported by the production app.
import XCTest

@MainActor final class FirstRunUITests: XCTestCase {
    private func app(language: String, selection: String, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--selection", selection, "--width", "320", "--type", large ? "large" : "default", "--theme", "light", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "tr" ? "tr_TR" : "en_US"]
        app.launch()
        return app
    }
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
    }
    func testEmptyEnglishSetupAndCancel() throws {
        let app = app(language: "en", selection: "empty")
        let select = app.buttons["Select Apps & Categories"]
        XCTAssertTrue(select.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Start Usage Cycle"].exists)
        XCTAssertFalse(app.buttons["Start Deep Focus"].exists)
        try audit(app)
        select.tap()
        XCTAssertTrue(app.navigationBars["Selection"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Select Apps & Categories"].waitForExistence(timeout: 5))
    }
    func testEmptyTurkishLargeText() throws {
        let app = app(language: "tr", selection: "empty", large: true)
        XCTAssertTrue(app.buttons["Uygulama ve Kategorileri Seç"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Kullanım Döngüsünü Başlat"].exists)
        XCTAssertFalse(app.buttons["Derin Odağı Başlat"].exists)
        try audit(app)
    }
    func testReadyEnglishEqualActionsAndFocusCancel() throws {
        let app = app(language: "en", selection: "valid")
        let cycle = app.buttons["Start Usage Cycle"]
        let focus = app.buttons["Start Deep Focus"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 8) && cycle.isEnabled)
        XCTAssertTrue(focus.exists && focus.isEnabled)
        XCTAssertFalse(app.buttons["Start BreakLoop"].exists)
        try audit(app)
        focus.tap()
        XCTAssertTrue(app.navigationBars["Deep Focus Setup"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Start Usage Cycle"].waitForExistence(timeout: 5))
    }
    func testReadyTurkishLargeText() throws {
        let app = app(language: "tr", selection: "valid", large: true)
        XCTAssertTrue(app.buttons["Kullanım Döngüsünü Başlat"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Derin Odağı Başlat"].exists)
        try audit(app)
    }
    func testUnsupportedAndUnreadableAreNotFirstUse() {
        for selection in ["websites", "readFailure"] {
            let app = app(language: "en", selection: selection)
            XCTAssertTrue(app.buttons["Review Selected Apps"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["Start Usage Cycle"].exists)
            XCTAssertFalse(app.buttons["Start Deep Focus"].exists)
            XCTAssertFalse(app.buttons["Select Apps & Categories"].exists)
            app.terminate()
        }
    }
}
