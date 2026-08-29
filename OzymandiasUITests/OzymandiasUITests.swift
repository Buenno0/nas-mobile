import XCTest

@MainActor
final class OzymandiasUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testServerLoginSessionAndLogoutFlow() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    let appearanceToggle = app.buttons["appearanceToggle"]
    XCTAssertTrue(appearanceToggle.waitForExistence(timeout: 3))
    let initialAppearance = appearanceToggle.value as? String
    appearanceToggle.tap()
    XCTAssertNotEqual(appearanceToggle.value as? String, initialAppearance)
    appearanceToggle.tap()

    let server = app.textFields["serverField"]
    XCTAssertTrue(server.waitForExistence(timeout: 3))
    app.buttons["validateServerButton"].tap()
    let loginButton = app.buttons["loginButton"]
    XCTAssertTrue(loginButton.waitForExistence(timeout: 3))
    XCTAssertFalse(server.exists)
    XCTAssertTrue(loginButton.isEnabled)

    app.textFields["usernameField"].tap()
    app.textFields["usernameField"].typeText("teste")
    app.secureTextFields["passwordField"].tap()
    app.secureTextFields["passwordField"].typeText("senha-segura")
    loginButton.tap()

    let confirmation = app.descendants(matching: .any)["sessionConfirmed"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    app.buttons["logoutButton"].tap()
    XCTAssertTrue(server.waitForExistence(timeout: 3))
  }
}
