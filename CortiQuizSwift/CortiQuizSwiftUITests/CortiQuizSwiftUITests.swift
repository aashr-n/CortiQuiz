//
//  CortiQuizSwiftUITests.swift
//  CortiQuizSwiftUITests
//
//  Created by Aashray N on 3/2/26.
//

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
        let card = app.staticTexts[mode]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "\(mode) card missing from menu")
        card.tap()
        return app
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
        for mode in ["Learn Mode", "Normal Mode", "Explore Mode", "MRI Mode", "MRI Quiz"] {
            XCTAssertTrue(app.staticTexts[mode].waitForExistence(timeout: 10), "\(mode) missing")
        }
        attachScreenshot(app, "Main menu")
    }

    @MainActor
    func testNormalModeAnswersAQuestion() throws {
        let app = open("Normal Mode")
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(app.staticTexts["Question 1 of 10"].exists)
        attachScreenshot(app, "Normal mode question")

        let options = app.buttons.matching(identifier: "answerOption")
        XCTAssertEqual(options.count, 4)
        options.firstMatch.tap()
        let next = app.buttons["Next →"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, "Normal mode feedback")

        next.tap()
        XCTAssertTrue(app.staticTexts["Question 2 of 10"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLearnModeRevealsACard() throws {
        let app = open("Learn Mode")
        let reveal = app.buttons["Reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: loadTimeout))
        reveal.tap()
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Study again"].exists)
        attachScreenshot(app, "Learn mode revealed")
    }

    @MainActor
    func testExploreSearchSelectsAStructure() throws {
        let app = open("Explore Mode")
        let search = app.textFields["Search structures…"]
        XCTAssertTrue(search.waitForExistence(timeout: loadTimeout))
        search.tap()
        search.typeText("putamen")
        let result = app.buttons["left putamen"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["Clear selection"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Explore selection")
    }

    @MainActor
    func testMRIModeSlicesAlongEachAxis() throws {
        let app = open("MRI Mode")
        let slider = app.sliders["Slice position"]
        XCTAssertTrue(slider.waitForExistence(timeout: loadTimeout))
        attachScreenshot(app, "MRI axial 50%")

        slider.adjust(toNormalizedSliderPosition: 0.3)
        XCTAssertTrue(app.staticTexts["Axial MRI Slice"].exists)
        attachScreenshot(app, "MRI axial 30%")

        for axis in ["Coronal", "Sagittal"] {
            app.buttons[axis].tap()
            XCTAssertTrue(app.staticTexts["\(axis) MRI Slice"].waitForExistence(timeout: 5))
            attachScreenshot(app, "MRI \(axis.lowercased())")
        }
    }

    @MainActor
    func testMRIQuizAnswersAQuestion() throws {
        let app = open("MRI Quiz")
        XCTAssertTrue(app.staticTexts["Identify the highlighted region"].waitForExistence(timeout: loadTimeout))
        attachScreenshot(app, "MRI quiz question")

        let options = app.buttons.matching(identifier: "answerOption")
        XCTAssertEqual(options.count, 4)
        options.firstMatch.tap()
        let next = app.buttons["Next →"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, "MRI quiz feedback")

        next.tap()
        XCTAssertTrue(app.buttons["Next →"].waitForNonExistence(timeout: 10))
        attachScreenshot(app, "MRI quiz second question")
    }
}
