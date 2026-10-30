// Isolated native UI harness; not a proof of Apple scheduling or shielding.
import XCTest
@MainActor final class DeepFocusCoexistenceUITests: XCTestCase {
    private func launch(_ runtime: String, turkish: Bool = false, large: Bool = false, screen: String = "dashboard") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--selection", "valid", "--runtime", runtime, "--width", "320", "--type", large ? "large" : "default", "--theme", turkish ? "dark" : "light", "--screen", screen, "-AppleLanguages", turkish ? "(tr)" : "(en)", "-AppleLocale", turkish ? "tr_TR" : "en_US"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    func testMonitoringHeroAndCompactFocusEntry() throws {
        let app = launch("active")
        let cycle = app.otherElements["dashboard.usageCycleCard"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["dashboard.deepFocusCard"].exists)
        XCTAssertTrue(cycle.staticTexts["Your cycle is running."].exists)
        XCTAssertFalse(app.staticTexts["Active Rule"].exists)
        let focus = app.buttons["dashboard.startDeepFocus"]
        XCTAssertEqual(app.buttons.matching(identifier: "dashboard.startDeepFocus").count, 1)
        XCTAssertGreaterThan(focus.frame.minY, cycle.frame.maxY)
        XCTAssertFalse(app.buttons["Apps & Categories"].exists)
        XCTAssertFalse(app.staticTexts["Usage Cycle Settings"].exists)
        reveal(focus, in: app)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
        focus.tap()
        XCTAssertTrue(app.navigationBars["Deep Focus Setup"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
    }
    func testMonitoringTurkishAccessibilityText() throws {
        let app = launch("active", turkish: true, large: true)
        let focus = app.buttons["dashboard.startDeepFocus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 8)); reveal(focus, in: app)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
    }
    func testOverlapShowsOnlyFocusHeroAndBackgroundNote() {
        let app = launch("overlap")
        XCTAssertTrue(app.staticTexts["Protect your focus."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["dashboard.usageCycleCard"].exists)
        XCTAssertFalse(app.staticTexts["Your cycle is running."].exists)
        XCTAssertTrue(app.staticTexts["Usage Cycle continues in the background."].exists)
        XCTAssertFalse(app.buttons["Stop Usage Cycle"].exists)
        XCTAssertTrue(app.buttons["End Deep Focus Early"].exists)
        XCTAssertFalse(app.buttons["dashboard.startDeepFocus"].exists)
    }
    func testOverlappingCooldownRetainsExtensionAndFocusEnd() {
        let app = launch("overlapCooldown")
        XCTAssertTrue(app.buttons["Extend by 15 min"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["End Deep Focus Early"].exists)
        XCTAssertFalse(app.otherElements["dashboard.usageCycleCard"].exists)
        XCTAssertFalse(app.buttons["dashboard.startDeepFocus"].exists)
    }
    func testIncompatibleRuntimeAndRecoveryControls() {
        for runtime in ["cooldown", "loading", "failure", "interrupted", "focus"] {
            let app = launch(runtime)
            XCTAssertFalse(app.buttons["dashboard.startDeepFocus"].exists, runtime)
            if runtime == "failure" || runtime == "interrupted" {
                XCTAssertTrue(app.buttons["Review Selected Apps"].exists)
                XCTAssertTrue(app.buttons["Refresh Status"].exists)
            }
            if runtime == "interrupted" { XCTAssertTrue(app.buttons["Stop Recorded Usage Cycle"].exists) }
            app.terminate()
        }
    }
    func testSelectionEditorHasNoDurationControls() throws {
        for turkish in [false, true] {
            let app = launch("inactive", turkish: turkish, large: turkish, screen: "selection")
            XCTAssertTrue(app.navigationBars[turkish ? "Seçim" : "Selection"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons[turkish ? "Uygulama ve Kategorileri Seç" : "Select Apps & Categories"].exists)
            XCTAssertFalse(app.staticTexts[turkish ? "Kullanım Sınırı" : "Usage Limit"].exists)
            XCTAssertFalse(app.staticTexts[turkish ? "Mola Süresi" : "Break Duration"].exists)
            let save = app.buttons[turkish ? "Kaydet" : "Save"]
            XCTAssertTrue(save.exists)
            XCTAssertFalse(save.isEnabled, "No opaque Apple selection is supplied by this UI fixture")
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
                // Native disabled controls are exempt from contrast requirements. Do not exempt enabled content.
                guard issue.auditType == .contrast, let element = issue.element else { return false }
                return element.elementType == .button && !element.isEnabled && ["Save", "Kaydet"].contains(element.label)
            }
            app.terminate()
        }
    }
    func testEnglishAndTurkishSettingsPrivacyTermsOnly() {
        for turkish in [false, true] {
            let app = launch("inactive", turkish: turkish, screen: "settings")
            let privacy = app.buttons[turkish ? "Gizlilik Politikası" : "Privacy Policy"]
            reveal(privacy, in: app)
            XCTAssertTrue(app.buttons[turkish ? "Kullanım Koşulları" : "Terms of Use"].exists)
            XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'KVKK'")).count, 0)
            app.terminate()
        }
    }
}
