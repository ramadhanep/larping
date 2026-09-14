//
//  ScreenshotTests.swift
//  larpingUITests
//
//  Captures the four main screens for README screenshots. Run manually:
//
//  xcodebuild -project larping.xcodeproj -scheme larping \
//    -destination 'platform=iOS Simulator,name=iPhone 17' \
//    -resultBundlePath /tmp/larping-screenshots.xcresult test \
//    -only-testing:larpingUITests/ScreenshotTests
//

import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreens() throws {
        let app = XCUIApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "location permission") { alert in
            if alert.buttons["Allow While Using App"].exists {
                alert.buttons["Allow While Using App"].tap()
                return true
            }
            return false
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "tab bar never appeared")

        let hikeRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '9.50 km'"))
            .firstMatch
        XCTAssertTrue(hikeRow.waitForExistence(timeout: 15), "no activity rows")
        sleep(2)
        capture("1-activities", of: app)

        hikeRow.tap()
        sleep(3)
        capture("1x-after-tap", of: app)
        let detailNav = app.navigationBars["Activity"]
        XCTAssertTrue(detailNav.waitForExistence(timeout: 8), "activity detail never opened")
        sleep(7)
        capture("2-activity-detail", of: app)

        detailNav.buttons.firstMatch.tap()
        sleep(2)

        app.tabBars.buttons["Record"].tap()
        sleep(3)
        app.tap()
        capture("3-record", of: app)

        app.tabBars.buttons["Stats"].tap()
        sleep(3)
        capture("4-stats", of: app)
    }

    @MainActor
    private func capture(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}