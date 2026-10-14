//
//  CortiQuizSwiftUITests.swift
//  CortiQuizSwiftUITests
//
//  Created by Aashray N on 3/2/26.
//

import UIKit
import XCTest

/// Smoke tests: open each mode from the menu, wait for its scene to load, and exercise
/// the main interaction. Screenshots are attached to the test results for visual review.
final class CortiQuizSwiftUITests: XCTestCase {

    /// Building a scene loads ~255 meshes; MRI Quiz also classifies slices.
    private let loadTimeout: TimeInterval = 180

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func open(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let card = menuRow(mode, in: app)
        XCTAssertTrue(card.exists, "\(mode) card missing from menu")
        card.tap()
        return app
    }

    /// A mode's row on the menu, scrolling down to it if the brain above pushed it off screen.
    @MainActor
    private func menuRow(_ mode: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.staticTexts[mode]
        _ = app.staticTexts["Learn"].waitForExistence(timeout: 10)
        for _ in 0..<4 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        return row
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMainMenuListsEveryMode() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Learn"].waitForExistence(timeout: 10))
        // Let the brain fade in before the screenshot.
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 4)
        attachScreenshot(app, "Main menu")
        for mode in ["Learn", "3D Quiz", "MRI Quiz", "3D Atlas", "MRI Slicer"] {
            XCTAssertTrue(menuRow(mode, in: app).exists, "\(mode) missing")
        }
        attachScreenshot(app, "Main menu scrolled")
    }

    @MainActor
    func testFirstLaunchInvitesYouToStart() throws {
        let app = XCUIApplication()
        // A string where the saved progress blob would be reads as "nothing saved yet",
        // for this launch only (the argument domain shadows the app's own defaults).
        app.launchArguments += ["-cortiquiz.progress.v1", "none"]
        app.launch()
        let start = app.buttons["Start Learning"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 4)
        attachScreenshot(app, "First launch")
        start.tap()
        XCTAssertTrue(app.buttons["Reveal"].waitForExistence(timeout: loadTimeout))
    }

    @MainActor
    func testQuizAtAnAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        menuRow("3D Quiz", in: app).tap()
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1.5)
        attachScreenshot(app, "3D quiz, large text")
        XCTAssertEqual(app.buttons.matching(identifier: "answerOption").count, 4)
    }

    /// iPad: the menu is a sidebar beside the open mode, and modes lay out side by side in
    /// landscape and stacked in portrait.
    @MainActor
    func testIPadLayouts() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        // The menu shows at launch even in portrait.
        let quiz = app.staticTexts["3D Quiz"]
        XCTAssertTrue(quiz.waitForExistence(timeout: 10))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 4)
        attachScreenshot(app, "iPad menu portrait")

        quiz.tap()
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 2)
        attachScreenshot(app, "iPad quiz portrait")

        // Portrait stacks the answers under the brain.
        let firstOption = app.buttons.matching(identifier: "answerOption").firstMatch
        let prompt = app.staticTexts["What structure is highlighted?"]
        XCTAssertGreaterThan(firstOption.frame.minY, app.windows.firstMatch.frame.midY)

        XCUIDevice.shared.orientation = .landscapeLeft
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 5)
        attachScreen("iPad quiz landscape")
        // Landscape puts them in a column beside it.
        XCTAssertGreaterThan(prompt.frame.minX, app.windows.firstMatch.frame.midX)
        firstOption.tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1)
        attachScreen("iPad quiz feedback")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The whole screen, in the device's portrait pixel orientation (rotate landscape shots
    /// to view them). After a rotation, `app.screenshot()` came out shifted and cropped.
    @MainActor
    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAboutSheetOpensAndCloses() throws {
        let app = XCUIApplication()
        app.launch()
        let about = app.buttons["About"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        about.tap()
        XCTAssertTrue(app.buttons["Reset Progress"].waitForExistence(timeout: 5))
        attachScreenshot(app, "About")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Reset Progress"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testQuizAnswersAQuestion() throws {
        let app = open("3D Quiz")
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(app.staticTexts["Question 1 of 10"].exists)
        // Let the scene fade in.
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1.5)
        attachScreenshot(app, "3D quiz question")

        let options = app.buttons.matching(identifier: "answerOption")
        XCTAssertEqual(options.count, 4)
        options.firstMatch.tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, "3D quiz feedback")

        next.tap()
        XCTAssertTrue(app.staticTexts["Question 2 of 10"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].exists, "Next should wait for an answer")
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1)
        attachScreenshot(app, "3D quiz second question")
    }

    @MainActor
    func testQuizSessionEndsWithSummary() throws {
        let app = open("3D Quiz")
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))

        for question in 1...10 {
            app.buttons.matching(identifier: "answerOption").firstMatch.tap()
            // The last question's button leads to the results instead.
            let next = app.buttons[question == 10 ? "See Results" : "Next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            if question == 10 { attachScreenshot(app, "3D quiz last answer") }
            next.tap()
        }
        let playAgain = app.buttons["Play Again"]
        XCTAssertTrue(playAgain.waitForExistence(timeout: 5))
        // Let the score ring finish filling in.
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1.5)
        attachScreenshot(app, "3D quiz summary")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Learn"].waitForExistence(timeout: 5), "Done should return to the menu")
    }

    @MainActor
    func testLearnModeRevealsACard() throws {
        let app = open("Learn")
        let reveal = app.buttons["Reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: loadTimeout))
        // The answer isn't on screen until it's revealed.
        XCTAssertFalse(app.buttons["Got it"].exists)
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1)
        attachScreenshot(app, "Learn mode card")
        reveal.tap()
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Study again"].exists)
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1)
        attachScreenshot(app, "Learn mode revealed")

        app.buttons["Got it"].tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1)
        attachScreenshot(app, "Learn mode second card")
    }

    @MainActor
    func testAtlasSearchSelectsAStructure() throws {
        let app = open("3D Atlas")
        let search = app.searchFields["Search structures"]
        XCTAssertTrue(search.waitForExistence(timeout: loadTimeout))
        search.tap()
        search.typeText("putamen")
        let result = app.buttons["Left putamen"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        attachScreenshot(app, "Atlas search suggestions")
        result.tap()
        XCTAssertTrue(app.buttons["Clear selection"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Atlas selection")
    }

    @MainActor
    func testMRISlicerSlicesAlongEachAxis() throws {
        let app = open("MRI Slicer")
        let slider = app.sliders["Slice position"]
        XCTAssertTrue(slider.waitForExistence(timeout: loadTimeout))
        attachScreenshot(app, "MRI axial 50%")

        slider.adjust(toNormalizedSliderPosition: 0.3)
        XCTAssertTrue(app.buttons["Axial"].isSelected)
        attachScreenshot(app, "MRI axial 30%")

        for axis in ["Coronal", "Sagittal"] {
            let segment = app.buttons[axis]
            segment.tap()
            XCTAssertTrue(segment.isSelected)
            attachScreenshot(app, "MRI \(axis.lowercased())")
        }
    }

    @MainActor
    func testMRISlicerNamesATappedRegion() throws {
        let app = open("MRI Slicer")
        let slice = app.descendants(matching: .any)["mriSlice"]
        XCTAssertTrue(slice.waitForExistence(timeout: loadTimeout))

        // Deep in the right cerebral white matter on the mid-axial slice (radiological: right
        // is on screen left), well clear of the unlabeled gaps between structures.
        slice.coordinate(withNormalizedOffset: CGVector(dx: 0.37, dy: 0.53)).tap()
        let clear = app.buttons["Clear selection"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        attachScreenshot(app, "MRI tapped region")

        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testMRIQuizAnswersAQuestion() throws {
        let app = open("MRI Quiz")
        XCTAssertTrue(app.staticTexts["Identify the highlighted region"].waitForExistence(timeout: loadTimeout))
        _ = app.staticTexts["no such element"].waitForExistence(timeout: 1.5)
        attachScreenshot(app, "MRI quiz question")

        let options = app.buttons.matching(identifier: "answerOption")
        XCTAssertEqual(options.count, 4)
        options.firstMatch.tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, "MRI quiz feedback")

        next.tap()
        XCTAssertTrue(app.buttons["Next"].waitForNonExistence(timeout: 10))
        attachScreenshot(app, "MRI quiz second question")
    }
}
