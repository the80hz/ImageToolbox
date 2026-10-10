import XCTest

final class ImageToolboxUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Pins the locale so assertions do not depend on the simulator language.
  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    return app
  }

  @MainActor
  func testOpensBase64ToolFromGrid() throws {
    let app = launchApp()

    let base64Card = app.buttons.matching(identifier: "tool.base64").firstMatch
    XCTAssertTrue(base64Card.waitForExistence(timeout: 5))

    base64Card.tap()

    XCTAssertTrue(app.navigationBars["Base64"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testDecodesBase64PngIntoImage() throws {
    // 1x1 PNG
    let pngBase64 =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    let app = launchApp()

    app.buttons.matching(identifier: "tool.base64").firstMatch.tap()

    let input = app.textViews.matching(identifier: "base64.input").firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText(pngBase64)

    app.buttons.matching(identifier: "base64.decode").firstMatch.tap()

    XCTAssertTrue(
      app.buttons.matching(identifier: "base64.decodedShare").firstMatch.waitForExistence(
        timeout: 5))
    XCTAssertFalse(app.staticTexts.matching(identifier: "base64.error").firstMatch.exists)
  }
}

extension ImageToolboxUITests {

  /// Picks a picture from the photo library and checks that its Base64 text appears.
  /// The sample picture is added to the simulator library with `simctl addmedia` before the run.
  @MainActor
  func testEncodesPickedPicture() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()

    app.buttons.matching(identifier: "tool.base64").firstMatch.tap()
    let pick = app.buttons.matching(identifier: "base64.pick").firstMatch
    XCTAssertTrue(pick.waitForExistence(timeout: 10))
    pick.tap()

    let photo = app.images.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20))
    photo.tap()

    let encoded = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Encoded'"))
      .firstMatch
    XCTAssertTrue(encoded.waitForExistence(timeout: 30))
  }

  /// Picks one picture for batch rename and checks the name on its row. The default pattern ends
  /// with `{ext}` and the default export format is PNG, so the row must show the PNG name that the
  /// batch writes.
  @MainActor
  func testBatchRenameShowsExportFileName() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText("Batch rename")
    app.buttons.matching(identifier: "tool.batchRename").firstMatch.tap()

    let pick = app.buttons.matching(identifier: "batchRename.pick").firstMatch
    XCTAssertTrue(pick.waitForExistence(timeout: 10))
    pick.tap()

    let photo = app.images.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20))
    photo.tap()
    // The multi-select picker confirms the selection with an Add button.
    let add = app.buttons["Add"].firstMatch
    if add.waitForExistence(timeout: 3) {
      add.tap()
    }

    XCTAssertTrue(app.staticTexts["photo_001.png"].waitForExistence(timeout: 30))
  }

  /// Picks a picture for the tone curves tool and checks that the curve editor appears.
  @MainActor
  func testCurvesEditorAppearsAfterPick() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText("Tone curves")
    app.buttons.matching(identifier: "tool.curves").firstMatch.tap()

    let pick = app.buttons.matching(identifier: "curves.pick").firstMatch
    XCTAssertTrue(pick.waitForExistence(timeout: 10))
    pick.tap()

    let photo = app.images.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20))
    photo.tap()

    let editor = app.descendants(matching: .any).matching(identifier: "curves.editor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 30))
  }

  /// Picks a picture, chooses QOI as the target and checks that the converted file can be shared.
  @MainActor
  func testFormatConversionOffersSharingAfterChoosingQOI() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText("Format conversion")
    app.buttons.matching(identifier: "tool.formatConversion").firstMatch.tap()

    let pick = app.buttons.matching(identifier: "formatConversion.pick").firstMatch
    XCTAssertTrue(pick.waitForExistence(timeout: 10))
    pick.tap()

    let photo = app.images.firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 20))
    photo.tap()

    let qoi = app.buttons.matching(identifier: "formatConversion.target.qoi").firstMatch
    XCTAssertTrue(qoi.waitForExistence(timeout: 30))
    qoi.tap()

    XCTAssertTrue(
      app.buttons.matching(identifier: "formatConversion.share").firstMatch.waitForExistence(
        timeout: 30))
  }
}
