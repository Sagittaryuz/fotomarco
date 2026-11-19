import XCTest

final class GalleryInteractionTests: XCTestCase {
    private func launch(seedBenchmark: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.19",
                               "-native.gps.enabled", "NO"]
        if seedBenchmark { app.launchArguments.append("-seedGalleryBenchmark") }
        app.launchArguments += extraArguments
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = springboard.alerts.buttons["Allow"].firstMatch
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        let error = app.alerts.buttons["OK"].firstMatch
        if error.waitForExistence(timeout: 3) { error.tap() }
        if seedBenchmark {
            let fullAccess = NSPredicate(format: "label IN %@", ["Allow Full Access", "Permitir Acesso Total"])
            let appButton = app.buttons.matching(fullAccess).firstMatch
            let systemButton = springboard.buttons.matching(fullAccess).firstMatch
            if appButton.waitForExistence(timeout: 3) {
                appButton.tap()
            } else if systemButton.waitForExistence(timeout: 3) {
                systemButton.tap()
            }
        }
        return app
    }

    func testGalleryCatalogMeasurement() {
        let app = launch(seedBenchmark: true)
        let fixtures = app.staticTexts["gallery-benchmark-fixtures"]
        XCTAssertTrue(fixtures.waitForExistence(timeout: 20))
        XCTAssertEqual(fixtures.label, "24 fotos pessoais de teste")
        var milliseconds: [Double] = []
        var counts: [String] = []
        for _ in 0..<3 {
            let entry = app.buttons["Abrir capturas"]
            XCTAssertTrue(entry.waitForExistence(timeout: 8))
            let start = ProcessInfo.processInfo.systemUptime
            entry.tap()
            let grid = app.collectionViews["momentra-gallery-grid"]
            XCTAssertTrue(grid.waitForExistence(timeout: 8))
            milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9.,]+ itens?")).firstMatch
            XCTAssertTrue(counter.waitForExistence(timeout: 5))
            counts.append(counter.label)
            app.buttons["Fechar galeria"].tap()
        }
        let measurements = "Itens: \(counts)\nAbrir até grade pronta (ms): \(milliseconds.map { Int($0.rounded()) })"
        let attachment = XCTAttachment(string: measurements)
        attachment.name = "Medição da galeria"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCloudCatalogSurvivesAppRelaunch() {
        let app = launch(extraArguments: ["-galleryCloudFixture", "-seedGalleryCloudFixture"])
        XCTAssertTrue(app.staticTexts["cloud-catalog-fixture"].waitForExistence(timeout: 8))
        openFixtureGallery(app)
        let sync = app.descendants(matching: .any)["gallery-sync-line"].firstMatch
        XCTAssertTrue(sync.waitForExistence(timeout: 4), "A linha deve aparecer durante a consulta simulada.")
        let quota = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Google Drive · Conta de teste")).firstMatch
        XCTAssertTrue(quota.exists)
        XCTAssertEqual(quota.value as? String, "31%")
        XCTAssertTrue(app.staticTexts["4 itens"].exists)
        snapshot("Catálogo e capacidade local durante a sincronização", app: app)
        XCTAssertTrue(sync.waitForNonExistence(timeout: 12))
        XCTAssertEqual(quota.value as? String, "31%")

        XCUIDevice.shared.press(.home)
        app.activate()
        openFixtureGallery(app)
        XCTAssertTrue(app.staticTexts["4 itens"].exists)
        app.terminate()

        let reopened = launch(extraArguments: ["-galleryCloudFixture"])
        XCTAssertTrue(reopened.staticTexts["cloud-catalog-fixture"].waitForExistence(timeout: 8))
        openFixtureGallery(reopened)
        snapshot("Catálogo da nuvem reaberto sem conta autenticada", app: reopened)
    }

    private func openFixtureGallery(_ app: XCUIApplication) {
        let count = app.staticTexts["4 itens"]
        let entry = app.buttons["Abrir capturas"]
        let cameraAlert = app.alerts.buttons["OK"].firstMatch
        for _ in 0..<3 {
            if cameraAlert.exists { cameraAlert.tap() }
            if count.exists { return }
            if entry.isHittable { entry.tap() }
            if count.waitForExistence(timeout: 2) { return }
        }
        XCTAssertTrue(count.waitForExistence(timeout: 8), "As três capturas e o item de nuvem devem aparecer.")
    }

    func testAppCapturesExcludeUntrackedPhotosEvenAfterVisitingFavorites() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let count = app.staticTexts["3 itens"]
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertEqual(app.collectionViews.cells.count, 3)
        let storage = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Armazenamento do iPhone")).firstMatch
        XCTAssertTrue(storage.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(storage.frame.height, 50)
        XCTAssertLessThan(storage.frame.maxY, app.collectionViews.firstMatch.frame.minY + 1)
        app.buttons["Favoritos"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum favorito"].waitForExistence(timeout: 8))
        app.buttons["Capturas"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertEqual(app.collectionViews.cells.count, 3)
        snapshot("Capturas e armazenamento", app: app)
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
        app.buttons["Mover para a lixeira"].tap()
        XCTAssertTrue(app.buttons["Selecionar"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Mostrar seleção (1)"].exists)
    }

    func testGallerySourceAndSearchClosePreserveFavoritesTab() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let filter = app.buttons["Filtrar por origem"]
        XCTAssertTrue(filter.waitForExistence(timeout: 8))
        XCTAssertEqual(filter.value as? String, "Todos")
        filter.tap()
        app.buttons["Local"].tap()
        XCTAssertEqual(filter.value as? String, "Local")
        app.buttons["Favoritos"].tap()
        let search = app.buttons["Buscar"]
        search.tap()
        XCTAssertTrue(app.textFields["gallery-content-search-field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        snapshot("Busca com teclado", app: app)
        app.buttons["Fechar busca"].tap()
        XCTAssertTrue(app.buttons["Buscar"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Favoritos"].isSelected)
        XCTAssertEqual(filter.value as? String, "Local")
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

    func testCameraPanelsShowCurrentChoices() {
        let app = launch()
        let profile = app.buttons["Escolher perfil do carimbo"]
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        XCTAssertEqual(profile.value as? String, "Padrão")
        profile.tap()
        let currentProfile = app.buttons["Padrão"].firstMatch
        XCTAssertTrue(currentProfile.waitForExistence(timeout: 5))
        snapshot("Perfil ativo na câmera", app: app)
        currentProfile.tap()

        let aspect = app.buttons["Proporção da foto"]
        aspect.tap()
        let square = app.buttons["Proporção 1:1"]
        XCTAssertTrue(square.waitForExistence(timeout: 5))
        square.tap()
        XCTAssertTrue(square.isSelected)
        snapshot("Painel de proporções", app: app)
        app.buttons["Proporção 4:3"].tap()
        app.buttons["Fechar proporções"].tap()
        XCTAssertTrue(square.waitForNonExistence(timeout: 5))
    }

    func testPhotoStylesAndStampOptionsAreReachable() {
        let app = launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Configurações")).firstMatch.tap()
        let styles = app.buttons["Estilos fotográficos"]
        if !styles.isHittable { app.swipeUp() }
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        styles.tap()
        let applyStyle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Usar ")).firstMatch
        XCTAssertTrue(applyStyle.waitForExistence(timeout: 5))
        snapshot("Estilos fotográficos", app: app)
        applyStyle.tap()

        let stamp = app.buttons["Layout e perfis"]
        for _ in 0..<3 where !stamp.isHittable { app.swipeUp() }
        XCTAssertTrue(stamp.isHittable)
        stamp.tap()
        XCTAssertTrue(app.buttons["Criar perfil"].waitForExistence(timeout: 5))
        let information = app.buttons["Informações"]
        XCTAssertTrue(information.isHittable)
        information.tap()
        XCTAssertTrue(information.isSelected)
        snapshot("Opções do carimbo", app: app)
    }

    func testSettingsUsesADraggableNativeSwitch() {
        let app = launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Configurações")).firstMatch.tap()
        let grid = app.switches["Grade"]
        if !grid.isHittable { app.swipeUp() }
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        XCTAssertEqual(grid.value as? String, "0")
        // UIKit exposes the entire native switch row to accessibility. Exercise physical positions.
        let right = grid.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
        let rightEdge = right.withOffset(CGVector(dx: -14, dy: 0))
        let leftEdge = right.withOffset(CGVector(dx: -43, dy: 0))
        let label = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
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
        let capsuleCenter = right.withOffset(CGVector(dx: -34, dy: 0))
        capsuleCenter.tap()
        XCTAssertEqual(grid.value as? String, "1")
        capsuleCenter.tap()
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
        let candidates = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Item "))
        XCTAssertTrue(candidates.allElementsBoundByIndex.contains { $0.isSelected })
        let additional = candidates.allElementsBoundByIndex.first { $0.isHittable && !$0.isSelected }
        XCTAssertNotNil(additional)
        additional?.tap()
        XCTAssertTrue(app.staticTexts["2 itens selecionados"].exists)
        snapshot("Compartilhar duas capturas", app: app)
        app.buttons["Compartilhar seleção"].tap()
        XCTAssertTrue(app.collectionViews["activityCollectionView"].waitForExistence(timeout: 12))
    }

    func testViewerSwipeDownKeepsGalleryOpen() {
        let app = launch()
        openCapture(app)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.72))
        origin.press(forDuration: 0.08, thenDragTo: end)
        XCTAssertTrue(app.buttons["Voltar à galeria"].waitForNonExistence(timeout: 10))
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        XCTAssertTrue(grid.cells.firstMatch.isHittable)
        XCTAssertEqual(grid.cells.count, 3)
        grid.cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Voltar à galeria"].waitForExistence(timeout: 8))
        origin.press(forDuration: 0.08, thenDragTo: end)
        XCTAssertTrue(app.buttons["Fechar galeria"].waitForExistence(timeout: 8))
        app.buttons["Fechar galeria"].tap()
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
        app.buttons["Lixeira"].tap()
        XCTAssertTrue(app.staticTexts["30 dias"].firstMatch.waitForExistence(timeout: 8))
        app.collectionViews.cells.firstMatch.tap()
        let restore = app.buttons["Restaurar"]
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 8))
        app.buttons["Capturas"].tap()
        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 8))
    }

    func testPhotoFitsAndTapAndPinchControlFullscreen() {
        let app = launch()
        openCapture(app)
        let image = app.descendants(matching: .any)["gallery-photo-viewport"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        let controls = app.buttons["Compartilhar"]
        XCTAssertLessThan(image.frame.maxY, controls.frame.minY)
        XCTAssertEqual(image.value as? String, "Tamanho normal")
        image.tap()
        XCTAssertTrue(controls.waitForNonExistence(timeout: 5))
        image.tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        image.doubleTap()
        XCTAssertTrue(controls.waitForNonExistence(timeout: 5))
        XCTAssertEqual(image.value as? String, "Ampliada")
        image.doubleTap()
        XCTAssertEqual(image.value as? String, "Tamanho normal")
        XCTAssertFalse(controls.exists)
        image.tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        image.pinch(withScale: 1.7, velocity: 1)
        XCTAssertEqual(image.value as? String, "Ampliada")
        snapshot("Visualizador com aproximação", app: app)
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
