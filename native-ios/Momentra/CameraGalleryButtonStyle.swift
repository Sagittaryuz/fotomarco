import SwiftUI

struct CameraGalleryButtonStyle: PrimitiveButtonStyle {
    let share: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.3).exclusively(before: TapGesture())
                .onEnded { result in
                    guard enabled else { return }
                    switch result {
                    case .first: share()
                    case .second: configuration.trigger()
                    }
                })
            .accessibilityAction { if enabled { configuration.trigger() } }
    }
}
