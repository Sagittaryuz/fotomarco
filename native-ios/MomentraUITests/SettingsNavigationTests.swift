import XCTest

final class SettingsNavigationTests: XCTestCase {
    func testLiveStyleRendersSyntheticFrameOnGPU() {
        let app = XCUIApplication()
        app.launchArguments += ["--test-style-preview"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Quadro apresentado"].waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Prévia de estilo em tempo real"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOverlappingMapPhotosRemainAccessible() {
        let app = XCUIApplication()
        app.launchArguments += ["--test-map-overlap"]
        app.launch()
        let marker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.map.marker.")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        XCTAssertFalse(app.scrollViews["gallery.map.photos"].exists)
        marker.tap()
        let first = app.buttons["gallery.map.photo.00000000-0000-4000-8000-000000000008"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.staticTexts["Selecionada 00000000-0000-4000-8000-000000000008"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Fotos sobrepostas no mapa"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        marker.tap()
        let last = app.buttons["gallery.map.photo.00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertTrue(app.staticTexts["Selecionada 00000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 5))
    }

    func testSettingsRowsAndCameraSwitchRespond() {
        let app = XCUIApplication()
        app.launchArguments += ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.71"]
        addUIInterruptionMonitor(withDescription: "Permissões do iOS") { alert in
            for title in ["Permitir", "Permitir ao Usar o App", "OK", "Allow", "Allow While Using App"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        let settings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Configurações")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Configurações principais"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        for title in ["Câmera", "Layout e perfis", "Armazenamento", "Preferências", "Sobre"] {
            let row = app.buttons[title]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Linha ausente: \(title)")
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Linha não abriu: \(title)")
            let submenuScreenshot = XCTAttachment(screenshot: app.screenshot())
            submenuScreenshot.name = "Configurações - \(title)"
            submenuScreenshot.lifetime = .keepAlways
            add(submenuScreenshot)
            if title == "Sobre" {
                XCTAssertTrue(app.staticTexts["Novidades desta versão"].waitForExistence(timeout: 5))
                  XCTAssertTrue(app.staticTexts["1. Segure uma foto para selecionar e continue pressionando para compartilhar a seleção."].exists)
            }
            if title == "Câmera" {
                let label = app.buttons["Grade"]
                XCTAssertTrue(label.waitForExistence(timeout: 5))
                // The style exposes a named label button and a nested native switch.
                // Scope to the row so the test cannot toggle a different option.
                let row = app.cells.containing(.button, identifier: "Grade").firstMatch
                let grid = row.switches.element(boundBy: 1)
                XCTAssertTrue(grid.waitForExistence(timeout: 5))
                let before = grid.value as? String
                grid.tap()
                let after = before == "1" ? "0" : "1"
                let changed = expectation(for: NSPredicate(format: "value == %@", after), evaluatedWith: grid)
                wait(for: [changed], timeout: 5)
                label.tap()
                if let before {
                    let restored = expectation(for: NSPredicate(format: "value == %@", before), evaluatedWith: grid)
                    wait(for: [restored], timeout: 5)
                }
            }
            if title == "Armazenamento" {
                let addAccount = app.buttons["Adicionar Conta"]
                XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
                addAccount.tap()
                XCTAssertTrue(app.buttons["Google Drive"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["OneDrive"].exists)
                let providerScreenshot = XCTAttachment(screenshot: app.screenshot())
                providerScreenshot.name = "Adicionar conta"
                providerScreenshot.lifetime = .keepAlways
                add(providerScreenshot)
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testCameraOptionsTrayAndMap() {
        let app = XCUIApplication()
        app.launchArguments += ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.71"]
        addUIInterruptionMonitor(withDescription: "Permissões do iOS") { alert in
            for title in ["Permitir", "Permitir ao Usar o App", "OK", "Allow", "Allow While Using App"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        let options = app.buttons["camera.options.open"]
        XCTAssertTrue(options.waitForExistence(timeout: 30))
        options.tap()
        let grid = app.buttons["camera.options.grid"]
        if !grid.waitForExistence(timeout: 5) {
            // A simulator has no camera and can show this app alert after the
            // initial tap; dismiss only that known alert and retry the action.
            let cameraUnavailable = app.alerts["Photomark"]
            if cameraUnavailable.staticTexts["Câmera indisponível neste aparelho."].exists {
                cameraUnavailable.buttons["OK"].tap()
                options.tap()
            }
        }
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        let original = grid.value as? String
        XCTAssertTrue(original == "Ativada" || original == "Desativada")
        if original == "Ativada" {
            grid.tap()
            let deactivated = expectation(for: NSPredicate(format: "value == %@", "Desativada"), evaluatedWith: grid)
            wait(for: [deactivated], timeout: 5)
        }
        grid.tap()
        let activated = expectation(for: NSPredicate(format: "value == %@", "Ativada"), evaluatedWith: grid)
        wait(for: [activated], timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Bandeja da câmera"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Fechar"].firstMatch.tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertEqual(options.value as? String, "Ajustes ativos")
        options.tap()
        let styles = app.buttons["camera.options.styles"]
        XCTAssertTrue(styles.waitForExistence(timeout: 5))
        styles.tap()
        let customize = app.buttons["camera.styles.customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["camera.styles.shutter"].exists)
        customize.tap()
        XCTAssertTrue(app.sliders["Paleta"].waitForExistence(timeout: 5))
        let stylesScreenshot = XCTAttachment(screenshot: app.screenshot())
        stylesScreenshot.name = "Personalização dos estilos"
        stylesScreenshot.lifetime = .keepAlways
        add(stylesScreenshot)
        let styleBack = app.buttons["camera.styles.back"]
        XCTAssertTrue(styleBack.waitForExistence(timeout: 5))
        styleBack.tap()
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        let disabledStyle = app.buttons["camera.style.Desativado"]
        XCTAssertTrue(disabledStyle.waitForExistence(timeout: 5))
        disabledStyle.tap()
        XCTAssertFalse(customize.exists)
        let naturalStyle = app.buttons["camera.style.Natural"]
        XCTAssertTrue(naturalStyle.waitForExistence(timeout: 5))
        naturalStyle.tap()
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        styleBack.tap()
        app.buttons["camera.options.map"].tap()
        XCTAssertTrue(app.navigationBars["Mapa"].waitForExistence(timeout: 10))
        app.buttons["Fechar"].firstMatch.tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(app.buttons["camera.options.grid"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.options.grid"].exists)
        options.tap()
        app.buttons["camera.options.styles"].tap()
        XCTAssertTrue(app.buttons["camera.styles.shutter"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.styles.customize"].exists)
        options.tap()
        app.buttons["camera.options.map"].tap()
        XCTAssertTrue(app.navigationBars["Mapa"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)).tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Mapa"].exists)
    }
}
