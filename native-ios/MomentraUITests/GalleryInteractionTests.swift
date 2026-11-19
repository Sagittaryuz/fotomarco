import XCTest

final class GalleryInteractionTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.16",
                               "-native.gps.enabled", "NO"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.buttons["Allow"].firstMatch
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        let error = app.alerts.buttons["OK"].firstMatch
        if error.waitForExistence(timeout: 3) { error.tap() }
        return app
    }

    func testGalleryMarksAndReviewsSelection() {
        let app = launch()
        let gallery = app.buttons["Abrir capturas"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        XCTAssertTrue(app.buttons["Capturas"].waitForExistence(timeout: 7))
        let select = app.buttons["Selecionar"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let first = app.collectionViews.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.47)).tap()
        XCTAssertTrue(app.buttons["Mostrar seleção (1)"].waitForExistence(timeout: 8))
        XCTAssertTrue(first.isSelected)
        app.buttons["Mostrar seleção (1)"].tap()
        XCTAssertTrue(app.staticTexts["1 item selecionado"].waitForExistence(timeout: 9))
        snapshot("Seleção em revisão", app: app)
        app.buttons["Desmarcar tudo"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum item selecionado"].waitForExistence(timeout: 7))
        app.buttons["Concluir revisão"].tap()
        XCTAssertTrue(app.buttons["Cancelar"].waitForExistence(timeout: 7))
    }

    func testSupportPanelClosesOnOutsideTap() {
        let app = launch()
        let mark = app.buttons["Momentra"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        mark.tap()
        let pix = app.staticTexts["649-9221-9172"]
        XCTAssertTrue(pix.waitForExistence(timeout: 7))
        snapshot("Painel de apoio", app: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.77)).tap()
        XCTAssertFalse(pix.exists)
    }

    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
