import AVFoundation
import AVKit
import ExtensionKit
import LockedCameraCapture
import SwiftUI

@main
struct MomentraCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCameraScreen(directory: session.sessionContentURL)
        }
    }
}

private struct LockedCameraScreen: View {
    @StateObject private var camera = LockedCameraModel()
    @State private var location = LockedLocation()
    @State private var context: MomentraCaptureContext?
    @State private var contextLoaded = false
    let directory: URL

    var body: some View {
        GeometryReader { geometry in
        let aspect = PhotoAspect(rawValue: context?.aspect ?? "4:3") ?? .standard
        let previewSize = aspect.fittedSize(in: geometry.size) ?? .zero
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session, device: camera.activeDevice,
                          onCaptureRotation: camera.updateCaptureRotation, focus: camera.focus,
                          focusHapticIntensity: context?.hapticFocusIntensity)
                .frame(width: previewSize.width, height: previewSize.height).clipped()
            VStack {
                HStack {
                    Text("Photomark").font(.headline)
                    Spacer()
                    if camera.capturing || !contextLoaded { ProgressView().tint(.white) }
                }.padding()
                if context?.position == "top" { stampPreview }
                Spacer()
                if context?.position != "top" { stampPreview }
                if let limitation = lockedStampLimitation {
                    Text(limitation).font(.caption2).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.horizontal)
                }
                HStack(spacing: 12) {
                    ForEach(camera.zoomOptions, id: \.self) { zoom in
                        Button(String(format: "%g×", Double(zoom))) { camera.setZoom(zoom) }
                            .padding(10).background(.black.opacity(0.7), in: Capsule())
                    }
                }.padding(.vertical, 12)
                Button { takePhoto() } label: {
                    Circle().fill(.white).frame(width: 76, height: 76)
                        .padding(5).overlay(Circle().stroke(.white, lineWidth: 3))
                }.disabled(camera.capturing || !camera.ready || !contextLoaded).padding(.bottom, 24).accessibilityLabel("Fotografar")
            }.foregroundStyle(.white)
        }
        }
        .onCameraCaptureEvent { event in
            if event.phase == .ended { takePhoto() }
        }
        .task {
            context = try? await MomentraCaptureIntent.appContext
            contextLoaded = true
            location.startIfAuthorized(context?.gpsEnabled == true)
            camera.start()
        }
        .onDisappear { camera.stop(); location.stop() }
        .alert("Photomark", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("OK", role: .cancel) { camera.error = nil }
        } message: { Text(camera.error ?? "") }
    }

    private var lockedStampLimitation: String? {
        guard contextLoaded else { return nil }
        guard let context else { return "Configuração do carimbo indisponível. Abra o Photomark." }
        guard context.stampEnabled else { return nil }
        let layout = context.layoutData.flatMap { data in
            data.count <= 2000 ? try? JSONDecoder().decode(StampLayout.self, from: data) : nil
        } ?? StampLayout()
        let mapUnavailable = context.gpsEnabled && layout.showsMap && (layout.template == .original || layout.template.usesMap)
        let logoUnavailable = context.hasLogo == true && layout.showsLogo && (layout.template == .original || layout.template.usesLogo)
        if mapUnavailable && logoUnavailable { return "Mapa e logotipo indisponíveis com a tela bloqueada." }
        if mapUnavailable { return "Mapa indisponível com a tela bloqueada." }
        if logoUnavailable { return "Logotipo indisponível com a tela bloqueada." }
        return nil
    }

    @ViewBuilder
    private var stampPreview: some View {
        if let context, context.stampEnabled {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let layout = context.layoutData.flatMap { try? JSONDecoder().decode(StampLayout.self, from: $0) } ?? StampLayout()
                if layout.template.hasFixedRenderer {
                    let snapshot = StampSnapshot(capturedAt: timeline.date, gpsEnabled: context.gpsEnabled,
                                                 location: location.location, heading: location.heading, layout: layout)
                    if let image = StampRenderer.overlay(size: CGSize(width: 320, height: 140), snapshot: snapshot, map: nil, address: nil) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 140)
                            .accessibilityLabel("Pré-visualização do carimbo")
                    }
                } else {
                VStack(alignment: .leading, spacing: 4) {
                    if !context.note.isEmpty { Text(context.note) }
                    Text(timeline.date, format: .dateTime.day().month().year().hour().minute().second())
                    if context.gpsEnabled, let fix = location.location,
                       abs(fix.timestamp.timeIntervalSince(timeline.date)) <= 60 {
                        Text(String(format: "Lat: %.6f  Lon: %.6f", fix.coordinate.latitude, fix.coordinate.longitude))
                    } else {
                        Text(context.gpsEnabled ? "Localização indisponível nesta captura" : "Localização desativada")
                    }
                }
                .font(context.compact ? .caption2 : .caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(.horizontal)
        }
    }

    private func takePhoto() {
        guard contextLoaded else { return }
        camera.capture(directory: directory, context: context, location: location.location, heading: location.heading)
    }
}
