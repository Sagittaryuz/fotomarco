import XCTest

final class SettingsNavigationTests: XCTestCase {
    func testSettingsRowsAndCameraSwitchRespond() {
        let app = XCUIApplication()
        app.launchArguments += ["-welcomeCompletedV1", "YES", "-lastPresentedVersion", "0.1.56"]
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

        for title in ["Câmera", "Layout e perfis", "Armazenamento", "Preferências", "Sobre"] {
            let row = app.buttons[title]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Linha ausente: \(title)")
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Linha não abriu: \(title)")
            if title == "Câmera" {
                let grid = app.switches["Grade"]
                XCTAssertTrue(grid.waitForExistence(timeout: 5))
                let before = grid.value as? String
                grid.tap()
                let after = before == "1" ? "0" : "1"
                let changed = expectation(for: NSPredicate(format: "value == %@", after), evaluatedWith: grid)
                wait(for: [changed], timeout: 5)
                let label = app.buttons["Grade"]
                XCTAssertTrue(label.waitForExistence(timeout: 5))
                label.tap()
                if let before {
                    let restored = expectation(for: NSPredicate(format: "value == %@", before), evaluatedWith: grid)
                    wait(for: [restored], timeout: 5)
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
