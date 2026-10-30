// Native geometry checks of the production BLCountdownFace; deterministic fixture seconds.
import XCTest
@MainActor final class CountdownLayoutUITests: XCTestCase {
    private let samples = [18000,7200,3601,3600,3599,3598,600,599,60,59,10,9,1,0,86400]
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func verify(width: Int, language: String, large: Bool, all: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screen","countdown","--width","\(width)","--type",large ? "large":"default","--theme",language == "tr" ? "dark":"light","--sample",all ? "0":"2","-AppleLanguages","(\(language))","-AppleLocale",language == "tr" ? "tr_TR":"en_US"]
        app.launch()
        let digits = element(app,"countdown.digits")
        XCTAssertTrue(digits.waitForExistence(timeout: 8))
        let ids = ["fixture.countdownCard","countdown.header","countdown.digits","countdown.footer"]
        let frames = Dictionary(uniqueKeysWithValues: ids.map { ($0, element(app,$0).frame) })
        let firstRing = large ? nil : CountdownPaintProbe.bounds(app, center: digits.frame, dark: language == "tr")
        if !large { XCTAssertNotNil(firstRing, "Visible circle paint must be measured") }
        for index in (all ? Array(samples.indices) : [2,3,4,5]) {
            XCTAssertTrue(element(app,"fixture.sample").label.hasPrefix("Sample \(index):"))
            for id in ids {
                let current = element(app,id).frame; let initial = frames[id]!
                XCTAssertEqual(current.midX, initial.midX, accuracy: 0.5, "\(id) x at \(samples[index]) / \(width) / \(language)")
                XCTAssertEqual(current.midY, initial.midY, accuracy: 0.5, "\(id) y at \(samples[index]) / \(width) / \(language)")
                XCTAssertEqual(current.height, initial.height, accuracy: 0.5, "\(id) height at \(samples[index])")
                if id == "countdown.dial" || id == "fixture.countdownCard" {
                    XCTAssertEqual(current.width, initial.width, accuracy: 0.5)
                }
            }
            if let firstRing {
                let ring = CountdownPaintProbe.bounds(app, center: digits.frame, dark: language == "tr")
                XCTAssertNotNil(ring)
                if let ring {
                    XCTAssertEqual(ring.midX, firstRing.midX, accuracy: 0.75)
                    XCTAssertEqual(ring.midY, firstRing.midY, accuracy: 0.75)
                    XCTAssertEqual(ring.width, firstRing.width, accuracy: 1)
                    XCTAssertEqual(ring.height, firstRing.height, accuracy: 1)
                }
            }
            if index == 14 { try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription]) }
            if index == 3 || index == 4 {
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "\(language)-\(width)-\(large ? "AX":"standard")-\(samples[index])"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            if index != (all ? 14 : 5) { app.buttons["Next sample"].tap() }
        }
        app.terminate()
    }
    func testAllFormattingBoundariesEnglishAndTurkish() throws {
        continueAfterFailure = false
        for language in ["en","tr"] { try verify(width:320,language:language,large:false,all:true) }
    }
    func testHourBoundaryAcrossWidthsAndAccessibility() throws {
        continueAfterFailure = false
        for language in ["en","tr"] {
            for width in [375,390,430] { try verify(width:width,language:language,large:false,all:false) }
            for width in [320,430] { try verify(width:width,language:language,large:true,all:false) }
        }
    }
}

// Measure the actual colored ring paint, not a fabricated accessibility rectangle.
// Constant low-opacity ambient fill is below the ring's chroma threshold; digits stay inside it.
enum CountdownPaintProbe {
    @MainActor static func bounds(_ app: XCUIApplication, center: CGRect, dark: Bool) -> CGRect? {
        let shot = app.screenshot().image; let scale = shot.scale
        let origin = CGPoint(x: center.midX-130, y: center.midY-130)
        guard let crop = shot.cgImage?.cropping(to: CGRect(x:origin.x*scale,y:origin.y*scale,width:260*scale,height:260*scale)) else { return nil }
        let w = crop.width, h = crop.height
        guard let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(crop,in:CGRect(x:0,y:0,width:w,height:h))
        let pixels = context.data!.assumingMemoryBound(to:UInt8.self)
        func ink(_ x: Int,_ y: Int) -> Bool {
            let i = (y*w+x)*4
            return Int(pixels[i+2])-Int(pixels[i]) > (dark ? 21 : 15)
        }
        let xs = (0..<w).filter { ink($0,h/2) }
        let ys = (0..<h).filter { ink(w/2,$0) }
        guard let left=xs.first,let right=xs.last,let top=ys.first,let bottom=ys.last else { return nil }
        let rect = CGRect(x:origin.x+CGFloat(left)/scale,y:origin.y+CGFloat(top)/scale,width:CGFloat(right-left+1)/scale,height:CGFloat(bottom-top+1)/scale)
        return rect.width > 180 && rect.height > 180 ? rect : nil
    }
}
