import SwiftUI

/// The label and the space beside it remain available for scrolling the form.
struct DirectionalSwitchStyle: ToggleStyle {
    var showsLabel = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.layoutDirection) private var layoutDirection

    func makeBody(configuration: Configuration) -> some View {
        if showsLabel {
            HStack {
                configuration.label.accessibilityHidden(true)
                Spacer(minLength: 12)
                capsule(configuration)
            }
        } else {
            capsule(configuration)
        }
    }

    private func capsule(_ configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .onChange(of: configuration.isOn) { _, _ in
                if isEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2) }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { value in
                let distance = value.translation
                guard isEnabled, abs(distance.width) >= 10, abs(distance.width) > abs(distance.height) * 1.25 else { return }
                let on = (distance.width > 0) == (layoutDirection == .leftToRight)
                // The native switch can also recognize the swipe. Apply its intended state once UIKit has finished tracking.
                DispatchQueue.main.async {
                    if configuration.isOn != on { configuration.isOn = on }
                }
            })
    }
}
