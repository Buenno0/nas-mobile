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
    appearanceToggle.tap()
    app.buttons["appearanceToggle"].tap()

    let server = app.textFields["serverField"]
    XCTAssertTrue(server.waitForExistence(timeout: 6))
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

    let home = app.staticTexts["homeHero"]
    XCTAssertTrue(home.waitForExistence(timeout: 3))
    home.tap()
    XCTAssertTrue(app.staticTexts["titleDetailName"].waitForExistence(timeout: 3))
    app.buttons["correctMatchButton"].tap()
    XCTAssertTrue(app.buttons["applyMatch-99"].waitForExistence(timeout: 3))
    app.buttons["applyMatch-99"].tap()
    XCTAssertTrue(app.staticTexts["titleDetailName"].waitForExistence(timeout: 3))
    app.buttons["primaryPlayButton"].tap()
    let closePlayerButton = app.buttons["closePlayerButton"]
    XCTAssertTrue(closePlayerButton.waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["playPauseButton"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["playbackSpeedButton"].exists)
    XCTAssertTrue(app.buttons["trackMenuButton"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["pictureInPictureButton"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)["airPlayButton"].waitForExistence(timeout: 3))
    closePlayerButton.tap()

    app.tabBars.buttons["Acervo"].tap()
    XCTAssertTrue(app.staticTexts["catalogLoaded"].waitForExistence(timeout: 3))
    // O botão de aparência flutuava aqui e roubava o toque do item de toolbar.
    XCTAssertFalse(app.buttons["appearanceToggle"].exists)
    XCTAssertTrue(app.buttons["catalogSortButton"].isHittable)

    app.tabBars.buttons["Coleções"].tap()
    XCTAssertTrue(app.staticTexts["Nenhuma coleção"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["createCollectionButton"].waitForExistence(timeout: 3))

    app.tabBars.buttons["Artistas"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["artistsLoaded"].waitForExistence(timeout: 3))
    app.buttons["artist-Artista Teste"].tap()
    XCTAssertTrue(app.staticTexts["artistDetailName"].waitForExistence(timeout: 3))
    app.buttons["playAllButton"].tap()
    XCTAssertTrue(app.buttons["closePlayerButton"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["nextEpisodeButton"].waitForExistence(timeout: 3))
    app.buttons["closePlayerButton"].tap()

    app.tabBars.buttons["Perfil"].tap()
    let confirmation = app.descendants(matching: .any)["sessionConfirmed"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    XCTAssertTrue(app.segmentedControls["appearancePicker"].waitForExistence(timeout: 3))
    app.buttons["serverDashboardButton"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["serverDashboardLoaded"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.descendants(matching: .any)["scanLiveIndicator"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["startScanButton"].exists)
    XCTAssertTrue(app.buttons["refreshMetadataButton"].exists)
    app.navigationBars.buttons["Perfil"].tap()
    XCTAssertTrue(app.buttons["logoutButton"].waitForExistence(timeout: 3))
    app.buttons["serverSettingsButton"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["settingsLoaded"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["saveSettingsButton"].exists)
    app.navigationBars.buttons["Perfil"].tap()
    XCTAssertTrue(app.buttons["logoutButton"].waitForExistence(timeout: 3))
    app.buttons["logoutButton"].tap()
    XCTAssertTrue(server.waitForExistence(timeout: 3))
  }
}

extension OzymandiasUITests {
  func testCaptureDetailScreen() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    app.buttons["validateServerButton"].tap()
    let loginButton = app.buttons["loginButton"]
    XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
    let user = app.textFields["usernameField"]
    user.tap()
    Thread.sleep(forTimeInterval: 0.6)
    user.typeText("teste")
    let pass = app.secureTextFields["passwordField"]
    pass.tap()
    Thread.sleep(forTimeInterval: 0.8)
    pass.typeText("senha-segura")
    loginButton.tap()
    let home = app.staticTexts["homeHero"]
    XCTAssertTrue(home.waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 1.5)
    save(XCUIScreen.main.screenshot(), as: "home.png")
    home.tap()
    XCTAssertTrue(app.staticTexts["titleDetailName"].waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 2.0)
    save(XCUIScreen.main.screenshot(), as: "detail-top.png")
    app.swipeUp()
    Thread.sleep(forTimeInterval: 1.2)
    save(XCUIScreen.main.screenshot(), as: "detail-bottom.png")
  }

  private func save(_ shot: XCUIScreenshot, as name: String) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    try? shot.pngRepresentation.write(to: url)
    print("CAPTURA: \(url.path)")
  }
}
