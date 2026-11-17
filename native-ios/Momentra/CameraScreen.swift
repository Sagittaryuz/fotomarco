import SwiftUI
import AVFoundation
import MapKit
import UniformTypeIdentifiers
import PhotosUI

struct CameraScreen: View {
    private enum CaptureMode: String, CaseIterable { case photo = "FOTO", video = "VÍDEO" }
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @StateObject private var pressure = PressureService()
    @StateObject private var weather = ForecastService()
    @StateObject private var updates = UpdateService()
    @StateObject private var googlePhotos = GooglePhotosManager()
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @AppStorage("native.stamp.enabled") private var stampEnabled = true
    @AppStorage("native.map.enabled") private var mapEnabled = false
    @AppStorage("native.address.enabled") private var addressEnabled = false
    @AppStorage("native.pressure.enabled") private var pressureEnabled = false
    @AppStorage("native.photos.enabled") private var saveToPhotos = true
    @AppStorage("native.stamp.size") private var stampSize = "regular"
    @AppStorage("native.stamp.position") private var stampPosition = "bottom"
    @AppStorage("native.stamp.dateFormat") private var dateFormat = "numeric"
    @AppStorage("native.stamp.font") private var stampFont = "system"
    @AppStorage("native.logo.corner") private var logoCorner = "auto"
    @AppStorage("native.map.scale") private var mapScale = "medium"
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
    @State private var showMap = false
    @State private var mapLocation: CLLocation?
    @State private var showSettingsImport = false
    @State private var showLogoImport = false
    @State private var showForecastTerms = false
    @State private var showGoogleConsent = false
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
                                .overlay(alignment: .topTrailing) {
                                    if updates.availableVersion != nil {
                                        Circle().fill(.red).frame(width: 10, height: 10).padding(3)
                                    }
                                }
                        }.accessibilityLabel(updates.availableVersion == nil ? "Configurações" : "Configurações, atualização disponível").disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
                    }.padding(.horizontal, 18)
                    if let version = updates.availableVersion {
                        Button("Atualização \(version) disponível") { showSettings = true }
                            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.75), in: Capsule())
                            .disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
                    }
                    if mode == .photo && stampEnabled && stampPosition == "top" { liveStamp }
                    Spacer(minLength: 8)
                    if countdown > 0 {
                        Text("\(countdown)").font(.system(size: 56, weight: .bold, design: .rounded))
                            .shadow(radius: 6).accessibilityLabel("\(countdown) segundos")
                        Spacer(minLength: 8)
                    }
                    if mode == .photo && stampEnabled && stampPosition != "top" { liveStamp }
                    if !camera.zoomOptions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(camera.zoomOptions, id: \.self) { factor in
                                Button { camera.setZoom(factor) } label: {
                                    Text(factor == 0.5 ? "0,5×" : "\(Int(factor))×").font(.caption.bold())
                                        .frame(width: 44, height: 36)
                                        .background(abs(camera.zoomFactor - factor) < 0.01 ? .white : .black.opacity(0.7), in: Capsule())
                                        .foregroundStyle(abs(camera.zoomFactor - factor) < 0.01 ? .black : .white)
                                }.accessibilityLabel("Zoom \(factor == 0.5 ? "meio" : String(Int(factor))) vezes")
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
                    HStack(spacing: 0) {
                            Button { showOriginals = true } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 44, height: 40)
                                    Text("Capturas").font(.caption2)
                                }
                            }
                            .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                            .accessibilityLabel("Abrir capturas")
                            .frame(maxWidth: .infinity)
                        Menu {
                            Button("HAMOA") { profile = "HAMOA" }
                            Button("PIRESCO") { profile = "PIRESCO" }
                            Button("Pessoal") { profile = "PESSOAL" }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "square.on.square").font(.title2).frame(width: 44, height: 40)
                                Text("Perfil").font(.caption2)
                            }
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Escolher perfil do carimbo")
                        .frame(maxWidth: .infinity)
                        Button {
                            if mode == .video {
                                if camera.isRecording { camera.stopRecording() } else { camera.startRecording(saveToPhotos: saveToPhotos) }
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
                        Button {
                            mapLocation = makeSnapshot(at: Date()).location
                            showMap = true
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "map.fill").font(.title2).frame(width: 44, height: 40)
                                Text("Mapa").font(.caption2)
                            }
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Abrir mapa")
                        .frame(maxWidth: .infinity)
                            Button { camera.flipCamera() } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "camera.rotate").font(.title2).frame(width: 44, height: 40)
                                    Text("Inverter").font(.caption2)
                                }
                            }.disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isRecording || camera.isFinishingRecording || countdown > 0)
                                .accessibilityLabel("Trocar câmera")
                                .frame(maxWidth: .infinity)
                    }.padding(.vertical, 18)
                }.foregroundStyle(.white)
            }
        }
        .statusBarHidden()
        .task { await updates.check() }
        .onAppear { camera.start(); location.setEnabled(gpsEnabled); pressure.setEnabled(pressureEnabled); refreshLogo() }
        .onDisappear { cancelCountdown(); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start(); location.setEnabled(gpsEnabled); pressure.setEnabled(pressureEnabled); Task { await updates.check() } }
            else { cancelCountdown(); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel() }
        }
        .onChange(of: gpsEnabled) { _, enabled in location.setEnabled(enabled) }
        .onChange(of: pressureEnabled) { _, enabled in pressure.setEnabled(enabled && scenePhase == .active) }
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
        .sheet(isPresented: $showOriginals) { OriginalsView(googlePhotos: googlePhotos) }
        .sheet(isPresented: $showMap) {
            NavigationStack {
                Group {
                    if let coordinate = mapLocation?.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))) {
                            Marker("Localização", coordinate: coordinate)
                        }
                    } else {
                        ContentUnavailableView("Localização indisponível", systemImage: "location.slash", description: Text("Ative o GPS nas configurações e aguarde uma localização recente."))
                    }
                }
                .navigationTitle("Mapa")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { showMap = false } } }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Atualizações") {
                        if let version = updates.availableVersion {
                            Text("Nova versão disponível: \(version)").font(.headline)
                            Link("Abrir instruções da atualização", destination: UpdateService.releasesURL)
                            Text("Baixe o IPA indicado e use o Signulous para assinar e instalar. A atualização não é instalada automaticamente.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(updates.checking ? "Verificando…" : "Verificar atualizações") {
                            Task { await updates.check(force: true) }
                        }.disabled(updates.checking)
                        if let status = updates.status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        Text("A consulta ao GitHub envia o IP da conexão para verificar versões publicadas.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                        Picker("Posição do logotipo na foto", selection: $logoCorner) {
                            Text("Automática").tag("auto")
                            Text("Superior esquerda").tag("top-left")
                            Text("Superior direita").tag("top-right")
                            Text("Inferior esquerda").tag("bottom-left")
                            Text("Inferior direita").tag("bottom-right")
                        }
                        Text("O logotipo pode ser deslocado para não cobrir o carimbo; a prévia é aproximada.")
                            .font(.footnote).foregroundStyle(.secondary)
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
                    Picker("Tamanho do carimbo", selection: $stampSize) {
                        Text("Normal").tag("regular")
                        Text("Compacto").tag("compact")
                    }.disabled(!stampEnabled)
                    Picker("Posição do carimbo", selection: $stampPosition) {
                        Text("Embaixo").tag("bottom")
                        Text("Em cima").tag("top")
                    }.disabled(!stampEnabled)
                    Picker("Data e hora", selection: $dateFormat) {
                        Text("Numérica").tag("numeric")
                        Text("Por extenso").tag("long")
                    }.disabled(!stampEnabled)
                    Picker("Fonte do carimbo", selection: $stampFont) {
                        Text("Sistema").tag("system")
                        Text("Serifada").tag("serif")
                        Text("Monoespaçada").tag("mono")
                    }.disabled(!stampEnabled)
                    Toggle("Salvar cópia no Fotos", isOn: $saveToPhotos)
                    Text("As capturas continuam guardadas no aplicativo. Use Capturas para compartilhá-las ou salvá-las no Fotos manualmente.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Mapa no carimbo", isOn: $mapEnabled).disabled(!gpsEnabled || !stampEnabled)
                    Picker("Tamanho do mapa", selection: $mapScale) {
                        Text("Pequeno").tag("small")
                        Text("Médio").tag("medium")
                        Text("Grande").tag("large")
                    }.disabled(!gpsEnabled || !stampEnabled || !mapEnabled)
                    Toggle("Endereço no carimbo", isOn: $addressEnabled).disabled(!gpsEnabled || !stampEnabled)
                    Toggle("Pressão do sensor", isOn: $pressureEnabled).disabled(!pressure.available || !stampEnabled)
                    if !pressure.available { Text("Sensor de pressão indisponível neste aparelho.").font(.footnote).foregroundStyle(.secondary) }
                    Text("Mapa e endereço usam serviços da Apple quando ativados e podem enviar a localização para obtê-los.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Section("Previsão meteorológica") {
                        Link("Ler termos da MET Norway", destination: URL(string: "https://docs.api.met.no/doc/TermsOfService")!)
                        Button("Consultar previsão") { showForecastTerms = true }
                            .disabled(!gpsEnabled || weather.isLoading)
                        Text("Consulta manual: envia sua localização aproximada e IP à MET Norway. Temperatura e umidade são previsões; pressão ao nível do mar não é a medida do sensor.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let status = weather.status { Text(status).font(.footnote) }
                        Link("MET Norway · CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    }
                    Section("Google Fotos pessoal") {
                        if googlePhotos.configured {
                            if googlePhotos.connected {
                                Button("Desconectar conta") { googlePhotos.signOut() }.disabled(googlePhotos.busy)
                            } else {
                                Button("Conectar Google Fotos") { showGoogleConsent = true }.disabled(googlePhotos.busy)
                            }
                            Text("O envio é manual e exclusivo para fotos pessoais. Conectar não envia fotos.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("A conexão nativa ainda não está configurada.").font(.footnote).foregroundStyle(.secondary)
                        }
                        if let message = googlePhotos.message { Text(message).font(.footnote) }
                    }
                    Text("Vídeos não recebem carimbo nesta versão em desenvolvimento.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle("Configurações")
                .toolbar { Button("Concluído") { showSettings = false } }
                .confirmationDialog("Leia os termos da MET Norway antes de aceitar. A consulta envia localização aproximada e IP.", isPresented: $showForecastTerms, titleVisibility: .visible) {
                    Button("Li e aceito os termos; consultar") { weather.consult(location: location.location, consent: true) }
                    Button("Cancelar", role: .cancel) {}
                }
                .confirmationDialog("Somente fotos pessoais. O Google pedirá permissão para adicionar fotos e ler itens criados pelo Momentra. Nenhuma foto será enviada ao conectar.", isPresented: $showGoogleConsent, titleVisibility: .visible) {
                    Button("Declaro uso pessoal e conecto") {
                        if let controller = Self.presentingController() { googlePhotos.connect(presenting: controller) }
                        else { googlePhotos.message = "Não foi possível abrir o login. Tente novamente." }
                    }
                    Button("Cancelar", role: .cancel) {}
                }
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
                        importMessage = "Ajustes compatíveis importados. Posições laterais do texto e cantos do mapa ainda não são aplicados; os logotipos devem ser importados separadamente."
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
        camera.capture(snapshot: snapshot, aspect: PhotoAspect(rawValue: photoAspect) ?? .standard, saveToPhotos: saveToPhotos)
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

    private var liveStamp: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            LiveStampView(snapshot: makeSnapshot(at: timeline.date))
        }.padding(.horizontal, 16)
            .padding(.top, stampPosition == "top" ? 12 : 0)
            .padding(.bottom, stampPosition == "top" ? 0 : 12)
    }

    private static func presentingController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private func makeSnapshot(at date: Date) -> StampSnapshot {
        StampSnapshot(capturedAt: date, gpsEnabled: gpsEnabled, mapEnabled: mapEnabled, addressEnabled: addressEnabled, title: activeTitle.wrappedValue, note: activeNote.wrappedValue, logo: logo, logoCorner: logoCorner, compact: stampSize == "compact", position: stampPosition, longDate: dateFormat == "long", fontStyle: stampFont, mapScale: mapScale, pressure: pressureEnabled ? pressure.sample : nil, forecast: gpsEnabled ? weather.current(location: location.location, at: date) : nil, location: location.location, heading: location.heading)
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
        saveToPhotos = s.allowGallery
        if let size = s.size { stampSize = size }
        if let position = s.position { stampPosition = position }
        if let format = s.timestampFormat { dateFormat = format }
        if let font = s.timestampFont { stampFont = font }
        if let scale = s.mapScale { mapScale = scale }
        if let corner = s.logoCorner { logoCorner = corner }
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
                .frame(width: snapshot.mapScale == "small" ? 60 : snapshot.mapScale == "large" ? 100 : 80,
                       height: snapshot.mapScale == "small" ? 75 : snapshot.mapScale == "large" ? 125 : 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id("\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(snapshot.lines, id: \.self) { line in
                    Text(line).font((snapshot.compact ? Font.caption2 : Font.caption).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        .fontDesign(snapshot.fontStyle == "mono" ? .monospaced : snapshot.fontStyle == "serif" ? .serif : .default)
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
