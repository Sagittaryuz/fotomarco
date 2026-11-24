import XCTest
import SwiftUI
import UIKit
@testable import Momentra

/// Produces review images at two phone sizes. Interactive system prompts and
/// live Liquid Glass refraction still require a real device or simulator UI run.
@MainActor final class OnboardingVisualTests: XCTestCase {
    func testOnboardingScreensProduceReviewImages() throws {
        let screens: [(String, AnyView)] = [
            ("welcome", AnyView(OnboardingIntroView {})),
            ("permissions", AnyView(OnboardingPermissionsView {})),
            ("login", AnyView(BusinessSignInView(submit: { _, _, _, _ in }, signInWithProvider: { _ in }, continueWithoutAccount: {}))),
            ("plans", AnyView(BusinessPlansView(onContinue: {})))
        ]
        for size in [CGSize(width: 375, height: 812), CGSize(width: 430, height: 932)] {
            for (name, view) in screens {
                let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark))
                renderer.proposedSize = ProposedViewSize(size)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let cg = try XCTUnwrap(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                        bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                    return true
                }
                XCTAssertTrue(rendered)
                let visiblePixels = stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, index in
                    count + (max(pixels[index], pixels[index + 1], pixels[index + 2]) > 30 ? 1 : 0)
                }
                XCTAssertGreaterThan(visiblePixels, cg.width * cg.height / 200, "Review image must not be blank")
                let attachment = XCTAttachment(image: image)
                attachment.name = "onboarding-\(name)-\(Int(size.width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
