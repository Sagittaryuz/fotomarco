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
                let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
                controller.overrideUserInterfaceStyle = .dark
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: size).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }
                XCTAssertGreaterThan(image.pngData()?.count ?? 0, 1_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "onboarding-\(name)-\(Int(size.width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
