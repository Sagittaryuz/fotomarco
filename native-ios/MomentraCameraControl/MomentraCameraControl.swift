import AppIntents
import SwiftUI
import WidgetKit

struct MomentraCameraControl: ControlWidget {
    static let kind = "br.com.momentra.camera.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MomentraCaptureIntent()) {
                Label("Photomark", systemImage: "camera.fill")
            }
        }
        .displayName("Abrir Photomark")
        .description("Abrir a câmera do Photomark.")
    }
}

@main
struct MomentraCameraControlBundle: WidgetBundle {
    var body: some Widget { MomentraCameraControl() }
}
