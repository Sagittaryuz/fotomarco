import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @AppStorage("native.stamp.enabled") private var stampEnabled = true
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Menu {
                            Button("Desligado") { camera.flashMode = .off }
                            Button("Automático") { camera.flashMode = .auto }
                            Button("Ligado") { camera.flashMode = .on }
                        } label: {
                            Image(systemName: camera.flashMode == .off ? "bolt.slash.fill" : camera.flashMode == .auto ? "bolt.badge.a" : "bolt.fill")
                                .font(.title2).frame(width: 44, height: 44)
                        }
                        .disabled(!camera.hasFlash || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Flash")
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
                    HStack {
                        Spacer().frame(maxWidth: .infinity)
                        Button {
                            let snapshot = stampEnabled ? StampSnapshot(capturedAt: Date(), gpsEnabled: gpsEnabled, location: location.location, heading: location.heading) : nil
                            camera.capture(snapshot: snapshot)
                        } label: {
                            Circle().fill(.white).padding(7)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .frame(width: min(82, geometry.size.width * 0.22), height: min(82, geometry.size.width * 0.22))
                        }
                        .disabled(!camera.ready || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Fotografar")
                        HStack {
                            Spacer()
                            Button { camera.flipCamera() } label: {
                                Image(systemName: "camera.rotate").font(.title2).frame(width: 44, height: 44)
                            }.disabled(!camera.ready || camera.isCapturing || camera.isSwitching)
                                .accessibilityLabel("Trocar câmera")
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    }.padding(.vertical, 18)
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
                    Toggle("Carimbo", isOn: $stampEnabled)
                    Text("O carimbo nativo está em desenvolvimento: inclui data e dados disponíveis do GPS. Mapa, endereço e demais opções ainda não foram migrados.")
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
