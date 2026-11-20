import XCTest
@testable import Momentra

final class StampTemplateTests: XCTestCase {
    func testLockedCaptureContextKeepsOnlySelectedTemplateWithoutChangingOriginal() throws {
        var layout = StampLayout()
        layout.template = .visit
        layout.templateValues = ["visit": ["Título": "Visita"], "workReport": ["Projeto": "Obra"]]
        let locked = layout.lockedCaptureLayout()
        XCTAssertEqual(locked.templateValue("Título"), "Visita")
        XCTAssertNil(locked.templateValues["workReport"])
        XCTAssertEqual(layout.templateValues["workReport"]?["Projeto"], "Obra")
        XCTAssertLessThan(try JSONEncoder().encode(locked).count, 2000)
    }

    func testLockedCaptureContextFitsAfterManyTemplatesAreCustomized() throws {
        var layout = StampLayout()
        for template in StampLayout.Template.allCases {
            layout.template = template
            for field in template.fields {
                layout.setTemplateValue(String(repeating: "A", count: 96), for: field)
            }
        }
        layout.template = .construction
        XCTAssertGreaterThan(try JSONEncoder().encode(layout).count, 2000)
        let data = try JSONEncoder().encode(layout.lockedCaptureLayout())
        XCTAssertLessThanOrEqual(data.count, 2000)
        let restored = try JSONDecoder().decode(StampLayout.self, from: data)
        XCTAssertEqual(restored.templateValue("Descrição"), String(repeating: "A", count: 96))
        XCTAssertEqual(layout.templateValues.count, StampLayout.Template.allCases.filter { !$0.fields.isEmpty }.count)
    }
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
