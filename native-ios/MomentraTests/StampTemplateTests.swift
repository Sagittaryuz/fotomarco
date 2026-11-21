import XCTest
import UIKit
@testable import Momentra

final class StampTemplateTests: XCTestCase {
    func testFixedTemplateLogoHitRegionsOnlyCoverExistingImages() throws {
        let size = CGSize(width: 390, height: 520)
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        func rects(_ template: StampLayout.Template, logo: UIImage?, extras: [UIImage?] = []) -> [CGRect] {
            var layout = StampLayout()
            layout.template = template
            let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, logo: logo, extraLogos: extras,
                                         location: nil, heading: nil, layout: layout)
            return StampRenderer.fixedLogoHitRects(snapshot: snapshot, in: size)
        }
        let box = StampRenderer.workReportRect(in: size)
        XCTAssertTrue(rects(.custom, logo: logo).isEmpty)
        XCTAssertTrue(rects(.portrait, logo: nil).isEmpty)
        let construction = rects(.construction, logo: logo, extras: [nil, logo])
        XCTAssertEqual(construction.count, 2)
        XCTAssertFalse(construction[0].intersects(construction[1]))
        for template in [StampLayout.Template.completed, .deliveryProof, .portrait, .shopee] {
            let rect = try XCTUnwrap(rects(template, logo: logo).first)
            XCTAssertTrue(box.contains(rect))
        }
    }

    func testFixedTemplateFieldsWarnForValuesThatExceedTheirRenderedWidth() {
        for template in StampLayout.Template.allCases {
            for field in template.fields {
                XCTAssertTrue(StampRenderer.customFieldFits("A", field: field, template: template), "\(template.rawValue).\(field)")
                XCTAssertFalse(StampRenderer.customFieldFits(String(repeating: "W", count: 96), field: field, template: template), "\(template.rawValue).\(field)")
            }
        }
    }
    func testMapPreferencesStayIndependentWhenChangingTemplates() throws {
        var layout = StampLayout()
        layout.showsMap = false
        layout.mapStyle = .satellite
        layout.selectTemplate(.map)
        XCTAssertTrue(layout.showsMap)
        XCTAssertEqual(layout.mapStyle, .map)
        layout.mapStyle = .satellite
        layout.selectTemplate(.largeMap)
        XCTAssertEqual(layout.mapStyle, .map)
        layout.selectTemplate(.map)
        XCTAssertEqual(layout.mapStyle, .satellite)
        layout.selectTemplate(.original)
        XCTAssertFalse(layout.showsMap)
        XCTAssertEqual(layout.mapStyle, .satellite)
        let restored = try JSONDecoder().decode(StampLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored, layout)
    }
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

    func testTemplateTextCannotBreakFixedLayoutWithPastedLineSeparators() {
        var layout = StampLayout()
        layout.template = .workReport
        layout.setTemplateValue("A\r\nB\tC\u{2028}D", for: "Projeto")
        let value = layout.templateValue("Projeto")
        XCTAssertFalse(value.contains(where: { $0.isNewline || $0 == "\t" }))
        XCTAssertTrue(value.contains("B C"))
    }
}
