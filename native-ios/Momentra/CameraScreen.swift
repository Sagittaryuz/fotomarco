import SwiftUI
import AVFoundation

struct CameraScreen: View {
    private enum CaptureMode: String, CaseIterable { case photo = "FOTO", video = "VÍDEO" }
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @AppStorage("native.stamp.enabled") private var stampEnabled = true
    @AppStorage("native.map.enabled") private var mapEnabled = false
    @AppStorage("native.address.enabled") private var addressEnabled = false
    @State private var showSettings = false
    @State private var mode: CaptureMode = .photo
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
                        .disabled(mode == .video || !camera.hasFlash || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Flash")
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title2)
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("Configurações").disabled(camera.isRecording || camera.isFinishingRecording)
                    }.padding(.horizontal, 18)
                    Spacer(minLength: 4)
                    CameraPreview(session: camera.session)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Spacer(minLength: 8)
                    Picker("Modo", selection: $mode) {
                        ForEach(CaptureMode.allCases, id: \.self) { value in
                            Text(value.rawValue).tag(value).disabled(value == .video && !camera.videoAvailable)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || camera.isSwitching)
                    HStack {
                        Spacer().frame(maxWidth: .infinity)
                        Button {
                            if mode == .video {
                                if camera.isRecording { camera.stopRecording() } else { camera.startRecording() }
                            } else {
                                let snapshot = stampEnabled ? StampSnapshot(capturedAt: Date(), gpsEnabled: gpsEnabled, mapEnabled: mapEnabled, addressEnabled: addressEnabled, location: location.location, heading: location.heading) : nil
                                camera.capture(snapshot: snapshot)
                            }
                        } label: {
                            Circle().fill(mode == .video ? .red : .white).padding(camera.isRecording ? 18 : 7)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .frame(width: min(82, geometry.size.width * 0.22), height: min(82, geometry.size.width * 0.22))
                        }
                        .disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isFinishingRecording)
                        .accessibilityLabel(mode == .photo ? "Fotografar" : camera.isRecording ? "Parar gravação" : "Gravar vídeo")
                        HStack {
                            Spacer()
                            Button { camera.flipCamera() } label: {
                                Image(systemName: "camera.rotate").font(.title2).frame(width: 44, height: 44)
                            }.disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isRecording || camera.isFinishingRecording)
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
                    Toggle("Mapa no carimbo", isOn: $mapEnabled).disabled(!gpsEnabled || !stampEnabled)
                    Toggle("Endereço no carimbo", isOn: $addressEnabled).disabled(!gpsEnabled || !stampEnabled)
                    Text("Mapa e endereço usam serviços da Apple quando ativados e podem enviar a localização para obtê-los.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Vídeos não recebem carimbo nesta versão em desenvolvimento.")
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
