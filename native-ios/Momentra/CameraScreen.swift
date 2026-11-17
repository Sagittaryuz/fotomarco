import SwiftUI
import AVFoundation
import MapKit

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
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()
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
                        .disabled(mode == .video || !camera.hasFlash || camera.isCapturing || camera.isSwitching || countdown > 0)
                        .accessibilityLabel("Flash")
                        Spacer()
                        Menu {
                            Button("Desligado") { timerSeconds = 0 }
                            Button("3 segundos") { timerSeconds = 3 }
                            Button("10 segundos") { timerSeconds = 10 }
                        } label: {
                            VStack(spacing: 0) {
                                Image(systemName: "timer").font(.title2)
                                if timerSeconds > 0 { Text("\(timerSeconds)s").font(.caption2) }
                            }.frame(width: 44, height: 44)
                        }
                        .disabled(mode == .video || countdown > 0 || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Temporizador")
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title2)
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("Configurações").disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
                    }.padding(.horizontal, 18)
                    Spacer(minLength: 8)
                    if countdown > 0 {
                        Text("\(countdown)").font(.system(size: 56, weight: .bold, design: .rounded))
                            .shadow(radius: 6).accessibilityLabel("\(countdown) segundos")
                        Spacer(minLength: 8)
                    }
                    if mode == .photo && stampEnabled {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let snapshot = StampSnapshot(capturedAt: timeline.date, gpsEnabled: gpsEnabled, mapEnabled: mapEnabled, addressEnabled: addressEnabled, location: location.location, heading: location.heading)
                            LiveStampView(snapshot: snapshot)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    if !camera.zoomOptions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(camera.zoomOptions, id: \.self) { factor in
                                Button { camera.setZoom(factor) } label: {
                                    Text("\(Int(factor))×").font(.caption.bold())
                                        .frame(width: 44, height: 36)
                                        .background(abs(camera.zoomFactor - factor) < 0.01 ? .white : .black.opacity(0.7), in: Capsule())
                                        .foregroundStyle(abs(camera.zoomFactor - factor) < 0.01 ? .black : .white)
                                }.accessibilityLabel("Zoom \(Int(factor)) vezes")
                            }
                        }.padding(.bottom, 10)
                    }
                    Picker("Modo", selection: $mode) {
                        ForEach(CaptureMode.allCases, id: \.self) { value in
                            Text(value.rawValue).tag(value).disabled(value == .video && !camera.videoAvailable)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || camera.isSwitching || countdown > 0)
                    HStack {
                        Spacer().frame(maxWidth: .infinity)
                        Button {
                            if mode == .video {
                                if camera.isRecording { camera.stopRecording() } else { camera.startRecording() }
                            } else {
                                if countdown > 0 { cancelCountdown() } else { schedulePhoto() }
                            }
                        } label: {
                            Circle().fill(mode == .video ? .red : .white).padding(camera.isRecording ? 18 : 7)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .frame(width: min(82, geometry.size.width * 0.22), height: min(82, geometry.size.width * 0.22))
                        }
                        .disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isFinishingRecording)
                        .accessibilityLabel(countdown > 0 ? "Cancelar temporizador" : mode == .photo ? "Fotografar" : camera.isRecording ? "Parar gravação" : "Gravar vídeo")
                        HStack {
                            Spacer()
                            Button { camera.flipCamera() } label: {
                                Image(systemName: "camera.rotate").font(.title2).frame(width: 44, height: 44)
                            }.disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isRecording || camera.isFinishingRecording || countdown > 0)
                                .accessibilityLabel("Trocar câmera")
                            Spacer()
                        }.frame(maxWidth: .infinity)
                    }.padding(.vertical, 18)
                }.foregroundStyle(.white)
            }
        }
        .statusBarHidden()
        .onAppear { camera.start(); location.setEnabled(gpsEnabled) }
        .onDisappear { cancelCountdown(); camera.stop(); location.setEnabled(false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start(); location.setEnabled(gpsEnabled) }
            else { cancelCountdown(); camera.stop(); location.setEnabled(false) }
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

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = 0
    }

    private func schedulePhoto() {
        guard camera.ready, !camera.isCapturing, !camera.isSwitching else { return }
        if timerSeconds == 0 { capturePhoto(); return }
        countdown = timerSeconds
        countdownTask = Task { @MainActor in
            while countdown > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            countdownTask = nil
            guard scenePhase == .active else { return }
            capturePhoto()
        }
    }

    private func capturePhoto() {
        let snapshot = stampEnabled ? StampSnapshot(capturedAt: Date(), gpsEnabled: gpsEnabled, mapEnabled: mapEnabled, addressEnabled: addressEnabled, location: location.location, heading: location.heading) : nil
        camera.capture(snapshot: snapshot)
    }
}

private struct LiveStampView: View {
    let snapshot: StampSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if snapshot.mapEnabled, let coordinate = snapshot.location?.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350)), interactionModes: []) {
                    Annotation("Localização", coordinate: coordinate) {
                        Circle().fill(.blue).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                .frame(width: 80, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id("\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(snapshot.lines, id: \.self) { line in
                    Text(line).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
                if snapshot.addressEnabled && snapshot.location != nil {
                    Text("Endereço após a captura").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
