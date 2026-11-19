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

        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.isHittable)
        let top = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.18))
        let bottom = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.83))
        let retry = app.buttons["Algumas contas estão indisponíveis. Tentar novamente"]
        XCTAssertFalse(retry.exists)
        top.press(forDuration: 0.05, thenDragTo: bottom)
        XCTAssertFalse(sync.exists)
        XCTAssertFalse(retry.exists)
        bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(retry.waitForExistence(timeout: 8), "Arrastar depois da última fileira deve tentar consultar a conta de teste.")
        XCTAssertTrue(app.staticTexts["4 itens"].exists)
        XCTAssertEqual(quota.value as? String, "31%")
        snapshot("Sincronização puxada pela última fileira", app: app)
        XCTAssertTrue(sync.waitForNonExistence(timeout: 12))

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
        let header = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@",
            "Hoje · .+ · (segunda-feira|terça-feira|quarta-feira|quinta-feira|sexta-feira|sábado|domingo)")).firstMatch
        XCTAssertTrue(header.exists)
        let storage = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Armazenamento do iPhone")).firstMatch
        XCTAssertTrue(storage.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(storage.frame.height, 50)
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertLessThan(storage.frame.maxY, grid.frame.minY + 1)
        let search = app.buttons["Buscar"].firstMatch
        XCTAssertTrue(search.isHittable)
        XCTAssertGreaterThanOrEqual(grid.frame.maxY, search.frame.maxY)
        app.buttons["Favoritos"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum favorito"].waitForExistence(timeout: 8))
        XCTAssertTrue(storage.exists)
        XCTAssertGreaterThan(storage.frame.height, 0)
        app.buttons["Lixeira"].tap()
        XCTAssertTrue(app.staticTexts["Lixeira vazia"].waitForExistence(timeout: 8))
        XCTAssertTrue(storage.exists)
        XCTAssertGreaterThan(storage.frame.height, 0)
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

    func testVideoEditingOpensAStampedPreviewAndSavesACopy() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        let video = grid.cells.element(boundBy: 3)
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        video.tap()
        let edit = app.buttons["Editar vídeo"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Carimbo do vídeo"].waitForExistence(timeout: 8))
        let save = app.buttons["Salvar cópia com carimbo"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        XCTAssertTrue(save.isEnabled)
        snapshot("Prévia do carimbo do vídeo", app: app)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 25))
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Carimbo do vídeo"].waitForExistence(timeout: 8))
        XCTAssertFalse(save.exists, "Uma cópia já carimbada deve abrir sem reaplicar o carimbo.")
    }

    func testIntermediateZoomReplacesTheLowerPresetAndCentersAboveShutter() {
        let samples = [("0.5", "meio", "0,5×"), ("1.8", "1", "1,8×"),
                       ("3.6", "2", "3,6×"), ("7.6", "4", "7,6×")]
        for (value, anchor, display) in samples {
            let app = launch(extraArguments: ["-qaCameraZoom", value])
            let selected = app.buttons["Zoom \(anchor) vezes"]
            let shutter = app.buttons["Fotografar"]
            XCTAssertTrue(selected.waitForExistence(timeout: 8))
            XCTAssertTrue(selected.isSelected)
            XCTAssertEqual(selected.value as? String, display)
            XCTAssertEqual(selected.frame.midX, shutter.frame.midX, accuracy: 2)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Zoom ")).count, 5)
            snapshot("Zoom \(display) centralizado", app: app)
            app.terminate()
        }
    }

    func testUpdateBannerChecksAgainAndOpensInstallerDirectly() {
        let app = launch(extraArguments: ["-qaUpdateFixture"])
        XCTAssertTrue(app.buttons["Atualização 9.9.1 disponível"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        app.activate()
        let updated = app.buttons["Atualização 9.9.2 disponível"]
        XCTAssertTrue(updated.waitForExistence(timeout: 8))
        updated.tap()
        XCTAssertTrue(app.alerts["Atualização do Momentra"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Instalador solicitado para 9.9.2"].exists)
        XCTAssertFalse(app.buttons["Concluído"].exists)
    }

    func testSupportPanelClosesOnOutsideTap() {
        let app = launch()
        let mark = app.buttons["Momentra"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        mark.tap()
        let pix = app.staticTexts["(64) 99921-9172"]
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

    func testGalleryGroupsCopyBadgesOnOneThumbnail() {
        let app = launch(extraArguments: ["-galleryCloudFixture", "-seedGalleryCloudFixture", "-duplicateGalleryCloudFixture"])
        XCTAssertTrue(app.staticTexts["cloud-catalog-fixture"].waitForExistence(timeout: 8))
        app.buttons["Abrir capturas"].tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        let badge = grid.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "No iPhone · Momentra, Google Drive · Conta de teste")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["28 itens"].exists)
        snapshot("Uma miniatura com duas origens", app: app)
    }

    func testRetappingGalleryTabsReturnsToNewestDate() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        let today = grid.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Hoje · ")).firstMatch
        let visible = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isHittable
        }
        for name in ["Capturas", "Favoritos", "Lixeira", "Capturas"] {
            let tab = app.buttons[name]
            tab.tap()
            let shown = XCTNSPredicateExpectation(predicate: visible, object: today)
            XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 10), .completed, name)
            grid.swipeDown(velocity: .fast)
            if today.exists && today.isHittable { grid.swipeDown(velocity: .fast) }
            XCTAssertFalse(today.exists && today.isHittable, "A rolagem deve revelar as fotos antigas em \(name).")
            tab.tap()
            let returned = XCTNSPredicateExpectation(predicate: visible, object: today)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed, name)
        }
        snapshot("Última fileira ao tocar na aba", app: app)
    }

    func testCameraThumbnailSharesOnlyTheDisplayedPhoto() {
        let app = launch()
        let thumbnail = app.buttons["Abrir capturas"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 8))
        thumbnail.tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        app.buttons["Fechar galeria"].tap()
        XCTAssertTrue(grid.waitForNonExistence(timeout: 8))
        XCTAssertTrue(thumbnail.isHittable)

        thumbnail.press(forDuration: 0.75)
        let activities = app.collectionViews["activityCollectionView"]
        XCTAssertTrue(activities.waitForExistence(timeout: 10))
        XCTAssertFalse(grid.exists)
        XCTAssertFalse(app.staticTexts["Foto ampliada"].exists)
        snapshot("Compartilhar foto pela miniatura da câmera", app: app)
        completeShareByCopying(in: app)
        XCTAssertTrue(thumbnail.isHittable)
        XCTAssertFalse(grid.exists)
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
        completeShareByCopying(in: app)
        XCTAssertTrue(app.staticTexts["Foto ampliada"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.collectionViews["momentra-gallery-grid"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Selecionar"].isHittable)
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
        completeShareByCopying(in: app)
        let share = app.buttons["Compartilhar"]
        XCTAssertTrue(app.buttons["Compartilhar seleção"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Voltar à galeria"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["gallery-photo-viewport"].firstMatch.isHittable)
        share.tap()
        XCTAssertTrue(app.staticTexts["1 item selecionado"].waitForExistence(timeout: 8))
    }

    func testCompletedBatchShareExitsSelectionMode() {
        let app = launch()
        app.buttons["Abrir capturas"].tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        let select = app.buttons["Selecionar"]
        select.tap()
        grid.cells.element(boundBy: 0).tap()
        grid.cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Mostrar seleção (2)"].exists)
        app.buttons["Compartilhar seleção"].tap()
        completeShareByCopying(in: app)
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertTrue(select.isHittable)
        XCTAssertTrue(app.buttons["Capturas"].isHittable)
        XCTAssertFalse(app.buttons["Mostrar seleção (2)"].exists)
        select.tap()
        XCTAssertTrue(app.buttons["Mostrar seleção (0)"].exists)
    }

    private func completeShareByCopying(in app: XCUIApplication) {
        let activities = app.collectionViews["activityCollectionView"]
        XCTAssertTrue(activities.waitForExistence(timeout: 12))
        let copy = activities.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "Copy", "Copiar")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 8))
        copy.tap()
        XCTAssertTrue(activities.waitForNonExistence(timeout: 10))
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

    func testGalleryReturnsToCameraWithHorizontalAndHeaderGestures() {
        let app = launch()
        let entry = app.buttons["Abrir capturas"]
        let close = app.buttons["Fechar galeria"]
        entry.tap()
        let grid = app.collectionViews["momentra-gallery-grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.55))
        let short = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.55))
        start.press(forDuration: 0.06, thenDragTo: short)
        XCTAssertTrue(close.isHittable, "Um gesto curto deve manter a galeria aberta.")
        let left = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        start.press(forDuration: 0.06, thenDragTo: left)
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        XCTAssertTrue(entry.isHittable)

        entry.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        let headerY = close.frame.midY / app.frame.height
        let header = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: headerY))
        let below = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: headerY + 0.32))
        header.press(forDuration: 0.06, thenDragTo: below)
        XCTAssertTrue(close.waitForNonExistence(timeout: 8))
        XCTAssertTrue(entry.isHittable)
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
