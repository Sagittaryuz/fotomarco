import XCTest
@testable import Momentra

final class StampTemplateTests: XCTestCase {
    func testExistingLayoutDecodesWithoutTemplateChanges() throws {
        let layout = try JSONDecoder().decode(StampLayout.self, from: Data("{}".utf8))
        XCTAssertEqual(layout.template, .original)
        XCTAssertTrue(layout.templateValues.isEmpty)
    }

    func testTemplateFieldsSurviveChangingModel() throws {
        var layout = StampLayout()
        layout.template = .workReport
        layout.templateValues[StampLayout.Template.workReport.rawValue] = ["Projeto": "Obra A", "Inspeção": "Piso"]
        layout.template = .visit
        layout.templateValues[StampLayout.Template.visit.rawValue] = ["Título": "Visita técnica"]
        let restored = try JSONDecoder().decode(StampLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored.template, .visit)
        XCTAssertEqual(restored.templateValues[StampLayout.Template.workReport.rawValue]?["Projeto"], "Obra A")
        XCTAssertEqual(restored.templateValues[StampLayout.Template.visit.rawValue]?["Título"], "Visita técnica")
        XCTAssertEqual(StampLayout.Template.allCases.count, 19)
    }

    func testOnlyFieldsBelongingToSelectedTemplateAreEditable() {
        var layout = StampLayout()
        layout.template = .workReport
        layout.setTemplateValue("Piso\nConcreto", for: "Inspeção")
        layout.setTemplateValue("Não deve ser salvo", for: "Encomenda")
        XCTAssertEqual(layout.templateValue("Inspeção"), "Piso Concreto")
        XCTAssertEqual(layout.templateValue("Encomenda"), "")
        layout.template = .delivery
        layout.setTemplateValue("Caixa", for: "Encomenda")
        layout.template = .workReport
        XCTAssertEqual(layout.templateValue("Inspeção"), "Piso Concreto")
    }
}
