import XCTest

final class GalleryInteractionTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.17",
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

    func testBatchDeleteLeavesSelectionMode() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        app.buttons["Selecionar"].tap()
        app.collectionViews.cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["Excluir seleção"].isEnabled)
        app.buttons["Excluir seleção"].tap()
        app.buttons["Excluir 1 itens"].tap()
        XCTAssertTrue(app.buttons["Selecionar"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Mostrar seleção (1)"].exists)
    }

    func testChangingGalleryTabByDraggingNativeSegmentAndSelectingDevicePhoto() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let tabs = app.segmentedControls.firstMatch
        let captures = tabs.buttons["Capturas"]
        let device = tabs.buttons["Celular"]
        XCTAssertTrue(captures.waitForExistence(timeout: 8))
        captures.press(forDuration: 0.15, thenDragTo: device)
        XCTAssertTrue(device.isSelected)
        device.press(forDuration: 0.15, thenDragTo: captures)
        XCTAssertTrue(captures.isSelected)
        device.tap()
        let allowPhotos = app.buttons["Permitir acesso"]
        if allowPhotos.exists {
            allowPhotos.tap()
            let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons
                .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Full Access", "Acesso Total")).firstMatch
            if permission.waitForExistence(timeout: 4) { permission.tap() }
        }
        let select = app.buttons["Selecionar"]
        XCTAssertTrue(select.waitForExistence(timeout: 8))
        select.tap()
        let first = app.collectionViews.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.buttons["Compartilhar seleção"].isEnabled)
        XCTAssertTrue(app.buttons["Excluir seleção"].isEnabled)
        app.buttons["Mostrar seleção (1)"].tap()
        XCTAssertTrue(app.staticTexts["1 item selecionado"].waitForExistence(timeout: 8))
        snapshot("Seleção do iPhone", app: app)
    }

    func testEditorSavesACopyAfterRotating() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let first = app.collectionViews.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        app.buttons["Editar foto"].tap()
        XCTAssertTrue(app.staticTexts["Editor Momentra"].waitForExistence(timeout: 8))
        let save = app.buttons["Salvar cópia"]
        XCTAssertFalse(save.isEnabled)
        app.buttons["Recortar"].tap()
        let rotate = app.buttons["Girar 90 graus"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 8))
        rotate.tap()
        XCTAssertTrue(save.isEnabled)
        app.buttons["Desfazer"].tap()
        XCTAssertFalse(save.isEnabled)
        app.buttons["Refazer"].tap()
        XCTAssertTrue(save.isEnabled)
        snapshot("Editor de foto", app: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["Editor Momentra"].waitForNonExistence(timeout: 14))
        XCTAssertTrue(app.buttons["Editar foto"].waitForExistence(timeout: 12))
    }

    func testSettingsUsesADraggableNativeSwitch() {
        let app = launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Configurações")).firstMatch.tap()
        let grid = app.switches["Grade"]
        if !grid.isHittable { app.swipeUp() }
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        XCTAssertEqual(grid.value as? String, "0")
        let rightEdge = grid.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -12, dy: 0))
        let leftEdge = rightEdge.withOffset(CGVector(dx: -32, dy: 0))
        leftEdge.press(forDuration: 0.15, thenDragTo: rightEdge)
        XCTAssertEqual(grid.value as? String, "1")
        rightEdge.press(forDuration: 0.15, thenDragTo: leftEdge)
        XCTAssertEqual(grid.value as? String, "0")
        snapshot("Interruptores nativos", app: app)
    }

    func testHoldingGalleryPhotoAutomaticallyOpensSystemShareSheet() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let first = app.collectionViews.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertFalse(first.buttons["Opções da captura"].exists)
        first.press(forDuration: 0.7)
        let copy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@", "Copy", "Copiar")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 12))
        snapshot("Compartilhamento rápido", app: app)
    }

    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
