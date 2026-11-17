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
    let directory: URL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LockedCameraPreview(session: camera.session, device: camera.activeDevice, onCaptureRotation: camera.updateCaptureRotation).ignoresSafeArea()
            VStack {
                HStack {
                    Text("Momentra").font(.headline)
                    Spacer()
                    if camera.capturing { ProgressView().tint(.white) }
                }.padding()
                Spacer()
                if let context, context.stampEnabled {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(alignment: .leading, spacing: 4) {
                            if !context.title.isEmpty { Text(context.title).bold() }
                            if !context.note.isEmpty { Text(context.note) }
                            Text(timeline.date, format: .dateTime.day().month().year().hour().minute().second())
                            if context.gpsEnabled, let fix = location.location,
                               abs(fix.timestamp.timeIntervalSince(timeline.date)) <= 60 {
                                Text(String(format: "Lat: %.6f  Lon: %.6f", fix.coordinate.latitude, fix.coordinate.longitude))
                            } else {
                                Text(context.gpsEnabled ? "Localização indisponível nesta captura" : "Localização desativada")
                            }
                        }
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    }.padding(.horizontal)
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
                }.disabled(camera.capturing || !camera.ready).padding(.bottom, 24)
            }.foregroundStyle(.white)
        }
        .onCameraCaptureEvent { event in
            if event.phase == .ended { takePhoto() }
        }
        .task {
            context = try? await MomentraCaptureIntent.appContext
            location.startIfAuthorized(context?.gpsEnabled == true)
            camera.start()
        }
        .onDisappear { camera.stop(); location.stop() }
        .alert("Momentra", isPresented: Binding(get: { camera.error != nil }, set: { if !$0 { camera.error = nil } })) {
            Button("OK", role: .cancel) { camera.error = nil }
        } message: { Text(camera.error ?? "") }
    }

    private func takePhoto() {
        camera.capture(directory: directory, context: context, location: location.location, heading: location.heading)
    }
}
