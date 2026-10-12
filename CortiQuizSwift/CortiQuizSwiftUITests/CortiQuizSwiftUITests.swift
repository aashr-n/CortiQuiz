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
        for mode in ["Learn", "3D Quiz", "MRI Quiz", "3D Atlas", "MRI Slicer"] {
            XCTAssertTrue(app.staticTexts[mode].waitForExistence(timeout: 10), "\(mode) missing")
        }
        attachScreenshot(app, "Main menu")
    }

    @MainActor
    func testQuizAnswersAQuestion() throws {
        let app = open("3D Quiz")
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))
        XCTAssertTrue(app.staticTexts["Question 1 of 10"].exists)
        attachScreenshot(app, "3D quiz question")

        let options = app.buttons.matching(identifier: "answerOption")
        XCTAssertEqual(options.count, 4)
        options.firstMatch.tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, "3D quiz feedback")

        next.tap()
        XCTAssertTrue(app.staticTexts["Question 2 of 10"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuizSessionEndsWithSummary() throws {
        let app = open("3D Quiz")
        XCTAssertTrue(app.staticTexts["What structure is highlighted?"].waitForExistence(timeout: loadTimeout))

        let next = app.buttons["Next"]
        for _ in 0..<10 {
            app.buttons.matching(identifier: "answerOption").firstMatch.tap()
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        let playAgain = app.buttons["Play Again"]
        XCTAssertTrue(playAgain.waitForExistence(timeout: 5))
        attachScreenshot(app, "3D quiz summary")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["MRI Slicer"].waitForExistence(timeout: 5), "Done should return to the menu")
    }

    @MainActor
    func testLearnModeRevealsACard() throws {
        let app = open("Learn")
        let reveal = app.buttons["Reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: loadTimeout))
        attachScreenshot(app, "Learn mode card")
        reveal.tap()
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Study again"].exists)
        attachScreenshot(app, "Learn mode revealed")
    }

    @MainActor
    func testAtlasSearchSelectsAStructure() throws {
        let app = open("3D Atlas")
        let search = app.searchFields["Search structures"]
        XCTAssertTrue(search.waitForExistence(timeout: loadTimeout))
        search.tap()
        search.typeText("putamen")
        let result = app.buttons["left putamen"]
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
