import SwiftUI

/// Retains the system switch and resolves horizontal swipes by direction.
struct DirectionalSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.layoutDirection) private var layoutDirection

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
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
