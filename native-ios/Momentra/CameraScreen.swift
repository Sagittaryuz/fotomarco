import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Text("MOMENTRA").font(.caption.bold()).tracking(2)
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title2)
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("Configurações")
                    }.padding(.horizontal, 18)
                    Spacer(minLength: 4)
                    CameraPreview(session: camera.session)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Spacer(minLength: 8)
                    Text("FOTO").font(.caption.bold()).tracking(1.5)
                        .padding(.vertical, 10).padding(.horizontal, 32)
                        .background(.white, in: Capsule()).foregroundStyle(.black)
                    Button { camera.capture() } label: {
                        Circle().fill(.white).padding(7)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .frame(width: min(82, geometry.size.width * 0.22), height: min(82, geometry.size.width * 0.22))
                    }
                    .disabled(!camera.ready || camera.isCapturing)
                    .accessibilityLabel("Fotografar")
                    .padding(.vertical, 18)
                }.foregroundStyle(.white)
            }
        }
        .statusBarHidden()
        .onAppear { camera.start(); location.setEnabled(gpsEnabled) }
        .onDisappear { camera.stop(); location.setEnabled(false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start(); location.setEnabled(gpsEnabled) }
            else { camera.stop(); location.setEnabled(false) }
        }
        .onChange(of: gpsEnabled) { _, enabled in location.setEnabled(enabled) }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Toggle("Localização", isOn: $gpsEnabled)
                    Text("A versão nativa está em desenvolvimento; o carimbo ainda não é aplicado às fotos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle("Configurações")
                .toolbar { Button("Concluído") { showSettings = false } }
            }
        }
        .alert("Momentra", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.clearError() } })) {
            Button("OK") { camera.clearError() }
        } message: { Text(camera.errorMessage ?? "") }
    }
}
