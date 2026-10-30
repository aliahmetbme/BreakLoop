// Explicit UI-state fixture operations, not real DeviceActivity execution.
import XCTest
@MainActor final class PremiumJourneyUITests: XCTestCase {
    private func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func launch(_ mode: String, journey: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--runtime",mode,"--selection","valid","--width","390","--type","default","--theme","dark","--breathing","-AppleLanguages","(en)","-AppleLocale","en_US"] + (journey ? ["--journey"]:[])
        app.launch(); return app
    }
    func testCompanionTruthfulnessAcrossOwnersAndUncertainty() {
        continueAfterFailure = false
        for (mode,title) in [("focus",""),("overlap","Usage Cycle active in background."),("overlapCooldown","Usage Cycle break active."),("overlapAttention","Usage Cycle needs attention"),("overlapPending","")] {
            let app = launch(mode); let indicator = find(app,"dashboard.backgroundCycle")
            if title.isEmpty { XCTAssertFalse(indicator.exists) }
            else {
                XCTAssertTrue(indicator.waitForExistence(timeout:8)); XCTAssertEqual(indicator.label,title)
                func pixels() -> Data {
                    let shot = app.screenshot().image; let scale = shot.scale; let r = indicator.frame
                    return shot.cgImage!.cropping(to: CGRect(x:r.minX*scale,y:r.minY*scale,width:r.width*scale,height:r.height*scale))!.dataProvider!.data! as Data
                }
                let p1 = pixels(); Thread.sleep(forTimeInterval:0.7); let p2 = pixels()
                if mode == "overlap" {
                    Thread.sleep(forTimeInterval:0.7)
                    XCTAssertTrue(p1 != p2 || p2 != pixels(), "Only verified normal monitoring gets a mini pulse")
                    let digits = find(app,"countdown.digits")
                    let dial = CountdownPaintProbe.bounds(app, center: digits.frame, dark: true)
                    XCTAssertNotNil(dial)
                    if let dial { XCTAssertGreaterThan(dial.minY,indicator.frame.maxY) }
                } else { XCTAssertEqual(p1,p2,"Cooldown/attention indicators do not pulse as healthy monitoring") }
            }
            app.terminate()
        }
    }
    func testLabelledFixtureStartFocusEndFocusAndOwnerChanges() {
        continueAfterFailure = false
        let app = launch("active",journey:true)
        XCTAssertTrue(app.staticTexts["Your cycle is running."].waitForExistence(timeout:8))
        Thread.sleep(forTimeInterval:3)
        let start = app.buttons["dashboard.startDeepFocus"]
        if !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.navigationBars["Deep Focus Setup"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Start Deep Focus (")).firstMatch.tap()
        XCTAssertTrue(find(app,"dashboard.backgroundCycle").waitForExistence(timeout:8))
        XCTAssertFalse(find(app,"dashboard.usageCycleCard").exists)
        Thread.sleep(forTimeInterval:3)
        let end = app.buttons["End Deep Focus Early"]
        if !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.staticTexts["Your cycle is running."].waitForExistence(timeout:8))
        Thread.sleep(forTimeInterval:3)
        // A separately owned break changes companion state instead of claiming healthy monitoring.
        if !start.isHittable { app.swipeDown() }
        start.tap(); app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Start Deep Focus (")).firstMatch.tap()
        app.buttons["Fixture break"].tap()
        XCTAssertEqual(find(app,"dashboard.backgroundCycle").label,"Usage Cycle break active.")
        app.buttons["Fixture stop cycle"].tap()
        XCTAssertFalse(find(app,"dashboard.backgroundCycle").exists)
        app.terminate()
    }
}
