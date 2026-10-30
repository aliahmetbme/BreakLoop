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

    func testBreathingForegroundBackgroundAndSystemReduceMotion() {
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
        XCTAssertNotEqual(first, ringPixels(app), "Active artwork breathes")
        XCTAssertEqual(title.frame, frame, "Title layout stays still")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let resumed = ringPixels(app)
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertNotEqual(resumed, ringPixels(app), "Breathing resumes in foreground")
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
    }
}
