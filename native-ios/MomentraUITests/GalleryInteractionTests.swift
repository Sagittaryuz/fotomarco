import XCTest

final class GalleryInteractionTests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.18",
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
        app.buttons["Mover 1 itens para a lixeira"].tap()
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
            let access = NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Allow Full Access", "Permitir Acesso Total")
            let visibleAccess = app.buttons.matching(access).firstMatch
            if visibleAccess.waitForExistence(timeout: 3) { visibleAccess.tap() }
            else {
                let systemAccess = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(access).firstMatch
                if systemAccess.exists { systemAccess.tap() }
                else {
                    // The remote Photos authorization panel can be visible outside both accessibility trees.
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.739)).tap()
                }
            }
            let cameraUnavailable = app.alerts.containing(.staticText, identifier: "Câmera indisponível neste aparelho.").firstMatch
            if cameraUnavailable.waitForExistence(timeout: 5) { cameraUnavailable.buttons["OK"].tap() }
            if !tabs.exists {
                app.buttons["Abrir capturas"].tap()
                XCTAssertTrue(device.waitForExistence(timeout: 8))
                device.tap()
            }
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
        XCTAssertLessThanOrEqual(grid.frame.width, 80, "A área do interruptor deve ter a largura da cápsula.")
        XCTAssertEqual(grid.value as? String, "0")
        let rightEdge = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.5))
        let leftEdge = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.5))
        let label = grid.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -110, dy: 0))
        label.tap()
        label.press(forDuration: 0.1, thenDragTo: label.withOffset(CGVector(dx: 50, dy: 0)))
        XCTAssertEqual(grid.value as? String, "0")
        // A swipe that starts beside the capsule must not be accepted even if it ends over the switch.
        label.press(forDuration: 0.1, thenDragTo: rightEdge)
        XCTAssertEqual(grid.value as? String, "0")
        leftEdge.press(forDuration: 0.15, thenDragTo: rightEdge)
        XCTAssertEqual(grid.value as? String, "1")
        rightEdge.press(forDuration: 0.15, thenDragTo: leftEdge)
        XCTAssertEqual(grid.value as? String, "0")
        let before = grid.frame.midY
        label.press(forDuration: 0.07, thenDragTo: label.withOffset(CGVector(dx: -18, dy: 115)))
        XCTAssertGreaterThan(grid.frame.midY, before + 20, "Arrastar sobre o texto deve rolar o formulário.")
        XCTAssertEqual(grid.value as? String, "0")
        grid.tap()
        XCTAssertEqual(grid.value as? String, "1")
        grid.tap()
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
        let activities = app.collectionViews["activityCollectionView"]
        XCTAssertTrue(activities.waitForExistence(timeout: 12))
        XCTAssertTrue(activities.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "Copy", "Copiar")).firstMatch.exists)
        snapshot("Compartilhamento rápido", app: app)
    }

    func testViewerAddsNearbyPhotosToNativeShare() {
        let app = launch()
        openCapture(app)
        XCTAssertTrue(app.buttons["Mostrar grade"].exists)
        XCTAssertTrue(app.buttons["Favoritar"].exists)
        app.buttons["Compartilhar"].tap()
        XCTAssertTrue(app.staticTexts["1 item selecionado"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Item 1"].isSelected)
        app.buttons["Item 2"].tap()
        XCTAssertTrue(app.staticTexts["2 itens selecionados"].exists)
        snapshot("Compartilhar duas capturas", app: app)
        app.buttons["Compartilhar seleção"].tap()
        XCTAssertTrue(app.collectionViews["activityCollectionView"].waitForExistence(timeout: 12))
    }

    func testViewerSwipeDownReturnsDirectlyToCamera() {
        let app = launch()
        openCapture(app)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.72))
        origin.press(forDuration: 0.08, thenDragTo: end)
        XCTAssertTrue(app.buttons["Voltar à galeria"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Abrir capturas"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Abrir capturas"].isHittable)
    }

    func testViewerTrashCanBeDismissedAndCaptureRestored() {
        let app = launch()
        openCapture(app)
        let trash = app.buttons["Excluir captura"]
        trash.tap()
        let confirm = app.buttons["Mover para a lixeira"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        snapshot("Confirmação da lixeira", app: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        trash.tap()
        confirm.tap()
        app.buttons["Voltar à galeria"].tap()
        app.buttons["Lixeira de Capturas"].tap()
        let restore = app.buttons["Restaurar"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        let previousCount = app.buttons.matching(identifier: "Restaurar").count
        restore.tap()
        let newCount = NSPredicate { _, _ in app.buttons.matching(identifier: "Restaurar").count == previousCount - 1 }
        expectation(for: newCount, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        app.buttons["Concluído"].firstMatch.tap()
        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 8))
    }

    private func openCapture(_ app: XCUIApplication) {
        app.buttons["Abrir capturas"].tap()
        let cell = app.collectionViews.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8))
        cell.tap()
        XCTAssertTrue(app.buttons["Compartilhar"].waitForExistence(timeout: 8))
    }

    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
