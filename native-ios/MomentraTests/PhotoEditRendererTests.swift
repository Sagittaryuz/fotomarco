import UIKit
import XCTest
@testable import Momentra

final class PhotoEditRendererTests: XCTestCase {
    func testExportRotatesAndCropsAtSourceResolutionWithoutChangingInput() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: source) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format)
        let photo = renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        try photo.write(to: source)
        var recipe = PhotoEditRecipe()
        recipe.turns = 1
        let rotated = try XCTUnwrap(UIImage(data: PhotoEditRenderer.export(source, recipe: recipe))?.cgImage)
        XCTAssertEqual(rotated.width, 80)
        XCTAssertEqual(rotated.height, 120)
        recipe.crop = .square
        recipe.filter = .noir
        recipe[.exposure] = 0.35
        recipe.strokes = [PhotoStroke(ink: .yellow, points: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8)])]
        let cropped = try XCTUnwrap(UIImage(data: PhotoEditRenderer.export(source, recipe: recipe))?.cgImage)
        XCTAssertEqual(cropped.width, 80)
        XCTAssertEqual(cropped.height, 80)
        XCTAssertEqual(try Data(contentsOf: source), photo)
    }
}
