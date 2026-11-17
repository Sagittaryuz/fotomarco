import SwiftUI
import AVFoundation
import MapKit
import UniformTypeIdentifiers
import PhotosUI

struct CameraScreen: View {
    private enum CaptureMode: String, CaseIterable { case photo = "FOTO", video = "VÍDEO" }
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @AppStorage("native.stamp.enabled") private var stampEnabled = true
    @AppStorage("native.map.enabled") private var mapEnabled = false
    @AppStorage("native.address.enabled") private var addressEnabled = false
    @AppStorage("native.photo.aspect") private var photoAspect = PhotoAspect.standard.rawValue
    @AppStorage("native.profile") private var profile = "HAMOA"
    @AppStorage("native.profile.hamoa.title") private var hamoaTitle = "HAMOA"
    @AppStorage("native.profile.hamoa.note") private var hamoaNote = ""
    @AppStorage("native.profile.piresco.title") private var pirescoTitle = "PIRESCO ENGENHARIA"
    @AppStorage("native.profile.piresco.note") private var pirescoNote = ""
    @AppStorage("native.profile.pessoal.title") private var pessoalTitle = "MOMENTRA"
    @AppStorage("native.profile.pessoal.note") private var pessoalNote = ""
    @AppStorage("native.profile.hamoa.logo") private var hamoaLogo = ""
    @AppStorage("native.profile.piresco.logo") private var pirescoLogo = ""
    @AppStorage("native.profile.pessoal.logo") private var pessoalLogo = ""
    @State private var showSettings = false
    @State private var showOriginals = false
    @State private var showSettingsImport = false
    @State private var showLogoImport = false
    @State private var importMessage: String?
    @State private var mode: CaptureMode = .photo
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var selectedLogo: PhotosPickerItem?
    @State private var logoLoading = false
    @State private var logo: UIImage?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let selectedAspect = mode == .video ? PhotoAspect.wide : (PhotoAspect(rawValue: photoAspect) ?? .standard)
            let previewSize = selectedAspect.fittedSize(in: geometry.size) ?? .zero
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session, device: camera.activeDevice, onCaptureRotation: camera.updateCaptureRotation)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
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
                        Menu {
                            ForEach(PhotoAspect.allCases, id: \.rawValue) { aspect in
                                Button(aspect.rawValue) { photoAspect = aspect.rawValue }
                            }
                        } label: {
                            Text(photoAspect).font(.caption.bold()).frame(width: 44, height: 44)
                        }
                        .disabled(mode == .video || countdown > 0 || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Proporção da foto")
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
                            let snapshot = makeSnapshot(at: timeline.date)
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
                        HStack {
                            Spacer()
                            Button { showOriginals = true } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 44, height: 40)
                                    Text("Originais").font(.caption2)
                                }
                            }
                            .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                            .accessibilityLabel("Abrir originais")
                            Spacer()
                        }.frame(maxWidth: .infinity)
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
        .onAppear { camera.start(); location.setEnabled(gpsEnabled); refreshLogo() }
        .onDisappear { cancelCountdown(); camera.stop(); location.setEnabled(false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start(); location.setEnabled(gpsEnabled) }
            else { cancelCountdown(); camera.stop(); location.setEnabled(false) }
        }
        .onChange(of: gpsEnabled) { _, enabled in location.setEnabled(enabled) }
        .onChange(of: profile) { _, _ in refreshLogo() }
        .onChange(of: selectedLogo) { _, item in
            guard let item else { return }
            let targetProfile = profile
            logoLoading = true
            Task { @MainActor in
                defer { logoLoading = false; selectedLogo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ProfileLogoStore.LogoError.invalid }
                    let name = try await Task.detached(priority: .utility) { try ProfileLogoStore.save(data) }.value
                    setLogo(name, for: targetProfile)
                    if profile == targetProfile { refreshLogo() }
                } catch {
                    importMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar o logotipo. A imagem anterior foi preservada."
                }
            }
        }
        .sheet(isPresented: $showOriginals) { OriginalsView() }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Perfil do carimbo") {
                        Picker("Perfil", selection: $profile) {
                            Text("HAMOA").tag("HAMOA")
                            Text("PIRESCO").tag("PIRESCO")
                            Text("Pessoal").tag("PESSOAL")
                        }
                        TextField("Título", text: activeTitle)
                        TextField("Observação", text: activeNote)
                        PhotosPicker(selection: $selectedLogo, matching: .images) {
                            Label("Escolher logotipo", systemImage: "photo")
                        }.disabled(logoLoading)
                        Button { showLogoImport = true } label: {
                            Label("Escolher logotipo dos Arquivos", systemImage: "folder")
                        }.disabled(logoLoading)
                        if !activeLogoName.isEmpty {
                            Button("Remover logotipo do perfil", role: .destructive) {
                                setLogo("", for: profile)
                                refreshLogo()
                            }.disabled(logoLoading)
                        }
                        Button("Importar ajustes do Scripting") { showSettingsImport = true }
                        Text("Exporte os ajustes e cada logotipo no Momentra para Scripting. Algumas opções ainda não são importadas.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                .fileImporter(isPresented: $showLogoImport, allowedContentTypes: [.image]) { result in
                    guard let url = try? result.get() else { return }
                    let targetProfile = profile
                    logoLoading = true
                    Task { @MainActor in
                        defer { logoLoading = false }
                        do {
                            let name = try await Task.detached(priority: .utility) {
                                let scoped = url.startAccessingSecurityScopedResource()
                                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                                let file = try FileHandle(forReadingFrom: url)
                                defer { try? file.close() }
                                let data = try file.read(upToCount: 20_000_001) ?? Data()
                                return try ProfileLogoStore.save(data)
                            }.value
                            setLogo(name, for: targetProfile)
                            if profile == targetProfile { refreshLogo() }
                        } catch {
                            importMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível importar o logotipo. A imagem anterior foi preservada."
                        }
                    }
                }
                .fileImporter(isPresented: $showSettingsImport, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        let data = try file.read(upToCount: 65_537) ?? Data()
                        let transfer = try SettingsTransfer.decode(data)
                        apply(transfer)
                        importMessage = "Ajustes compatíveis importados. Logotipos e opções ainda não implementadas permanecem no Scripting."
                    } catch {
                        importMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível importar o arquivo. Nenhuma configuração foi alterada."
                    }
                }
                .alert("Momentra", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                    Button("OK") { importMessage = nil }
                } message: { Text(importMessage ?? "") }
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
        let snapshot = stampEnabled ? makeSnapshot(at: Date()) : nil
        camera.capture(snapshot: snapshot, aspect: PhotoAspect(rawValue: photoAspect) ?? .standard)
    }

    private var activeTitle: Binding<String> {
        switch profile {
        case "PIRESCO": return $pirescoTitle
        case "PESSOAL": return $pessoalTitle
        default: return $hamoaTitle
        }
    }

    private var activeNote: Binding<String> {
        switch profile {
        case "PIRESCO": return $pirescoNote
        case "PESSOAL": return $pessoalNote
        default: return $hamoaNote
        }
    }

    private func makeSnapshot(at date: Date) -> StampSnapshot {
        StampSnapshot(capturedAt: date, gpsEnabled: gpsEnabled, mapEnabled: mapEnabled, addressEnabled: addressEnabled, title: activeTitle.wrappedValue, note: activeNote.wrappedValue, logo: logo, location: location.location, heading: location.heading)
    }

    private var activeLogoName: String {
        switch profile {
        case "PIRESCO": return pirescoLogo
        case "PESSOAL": return pessoalLogo
        default: return hamoaLogo
        }
    }

    private func setLogo(_ name: String, for profileID: String) {
        switch profileID {
        case "PIRESCO": pirescoLogo = name
        case "PESSOAL": pessoalLogo = name
        default: hamoaLogo = name
        }
    }

    private func refreshLogo() { logo = ProfileLogoStore.load(activeLogoName) }

    private func apply(_ transfer: SettingsTransfer) {
        let s = transfer.settings
        guard let h = s.profiles["HAMOA"], let p = s.profiles["PIRESCO"], let personal = s.profiles["PESSOAL"] else { return }
        hamoaTitle = h.title; hamoaNote = h.note
        pirescoTitle = p.title; pirescoNote = p.note
        pessoalTitle = personal.title; pessoalNote = personal.note
        profile = s.profile; stampEnabled = s.stamp; gpsEnabled = s.gps; mapEnabled = s.map
        photoAspect = s.aspectRatio
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
            if let logo = snapshot.logo {
                Image(uiImage: logo).resizable().scaledToFit().frame(width: 38, height: 38)
                    .accessibilityLabel("Logotipo do perfil")
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
