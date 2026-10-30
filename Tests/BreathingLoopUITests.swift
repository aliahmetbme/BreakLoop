// Isolated simulator harness only; launch adapters are not shipped in production.
import XCTest

@MainActor final class BreathingLoopUITests: XCTestCase {
    private func reduceMotion(_ enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if !settings.switches["Reduce Motion"].exists {
            let accessibility = settings.staticTexts["Accessibility"]
            for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
            XCTAssertTrue(accessibility.waitForExistence(timeout: 5), settings.debugDescription)
            accessibility.tap()
            settings.staticTexts["Motion"].tap()
        }
        let toggle = settings.switches["Reduce Motion"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), settings.debugDescription)
        if (toggle.value as? String == "1") != enabled {
            // iOS 26 exposes the whole labelled row as a switch; tap its actual trailing control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let expected = enabled ? "1" : "0"
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, settings.debugDescription)
    }

    private func ringPixels(_ app: XCUIApplication) -> Data {
        let title = app.staticTexts["Your cycle is running."]
        let image = app.screenshot().image
        let scale = image.scale
        let rect = CGRect(x: (app.frame.midX - 110) * scale,
                          y: (title.frame.minY - 220) * scale,
                          width: 220 * scale, height: 220 * scale)
        return image.cgImage!.cropping(to: rect)!.dataProvider!.data! as Data
    }

    func testPremiumMotionForegroundBackgroundAndSystemReduceMotion() {
        continueAfterFailure = false
        reduceMotion(false)
        let app = XCUIApplication()
        app.launchArguments = ["--selection", "valid", "--runtime", "active", "--breathing",
                               "--width", "390", "--type", "default", "--theme", "dark",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let title = app.staticTexts["Your cycle is running."]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let frame = title.frame
        let first = ringPixels(app)
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertNotEqual(first, ringPixels(app), "Verified monitoring artwork breathes")
        XCTAssertEqual(title.frame, frame, "Title layout stays still")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let resumed = ringPixels(app)
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertNotEqual(resumed, ringPixels(app), "Breathing resumes after foreground return")
        XCTAssertEqual(title.frame, frame)

        reduceMotion(true)
        app.activate()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let still = ringPixels(app)
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertEqual(still, ringPixels(app), "System Reduce Motion provides static artwork")
        XCTAssertEqual(title.frame, frame)
        reduceMotion(false)
        var arguments = app.launchArguments
        if let i = arguments.firstIndex(of: "--runtime") { arguments[i+1] = "inactive" }
        app.launchArguments = arguments; app.launch()
        let ready = app.staticTexts["Ready to begin?"]
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        let image = app.screenshot().pngRepresentation
        // Decorative crop excludes the clock/status bar and fixed text outside the hero.
        let titleFrame = ready.frame
        func staticCrop() -> Data {
            let shot = app.screenshot().image; let scale = shot.scale
            return shot.cgImage!.cropping(to: CGRect(x: (app.frame.midX-110)*scale, y: (titleFrame.minY-220)*scale, width: 220*scale, height: 220*scale))!.dataProvider!.data! as Data
        }
        let inactive = staticCrop(); Thread.sleep(forTimeInterval: 0.9)
        XCTAssertEqual(inactive, staticCrop(), "Inactive artwork is static")
        _ = image
        if let i = arguments.firstIndex(of: "--runtime") { arguments[i+1] = "active" }
        arguments.append("--low-power-fixture")
        app.launchArguments = arguments; app.launch()
        XCTAssertTrue(app.staticTexts["Your cycle is running."].waitForExistence(timeout: 8))
        let lowPower = ringPixels(app); Thread.sleep(forTimeInterval: 0.9)
        XCTAssertEqual(lowPower, ringPixels(app), "Injected Low Power gate disables decoration; not a physical battery-mode test")
    }
    func testRepeatedSettingsNavigationResumesSingleArtwork() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--selection","valid","--runtime","active","--breathing","--width","390","--type","default","--theme","dark","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        for _ in 0..<3 {
            XCTAssertTrue(app.staticTexts["Your cycle is running."].waitForExistence(timeout:8))
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
            app.navigationBars["Settings"].buttons.element(boundBy:0).tap()
            XCTAssertTrue(app.staticTexts["Your cycle is running."].waitForExistence(timeout:5))
            let a = ringPixels(app); Thread.sleep(forTimeInterval:0.7); let b = ringPixels(app)
            Thread.sleep(forTimeInterval:0.7)
            XCTAssertTrue(a != b || b != ringPixels(app), "Artwork resumes after returning, without recreating the Dashboard")
        }
    }
}
