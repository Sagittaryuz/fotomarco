import SwiftUI
import AVFoundation
import AVKit
import MapKit
import UniformTypeIdentifiers
import PhotosUI
import ImageIO
import GoogleSignIn

struct CameraScreen: View {
    private enum CaptureMode: String, CaseIterable { case photo = "FOTO", video = "VÍDEO" }
    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()
    @StateObject private var addressPreview = AddressPreviewService()
    @StateObject private var pressure = PressureService()
    @StateObject private var weather = ForecastService()
    @StateObject private var updates = UpdateService()
    @StateObject private var directUpdate = DirectUpdateAccess.shared
    @StateObject private var googlePhotos = GooglePhotosManager.shared
    @StateObject private var stampProfiles = StampProfilesStore()
    @AppStorage("native.camera.photoStyle") private var photoStyle = MomentraPhotoStyle.natural.rawValue
    @AppStorage("native.camera.grid") private var showGrid = false
    @AppStorage("native.camera.scanQR") private var scanQR = true
    @AppStorage("native.camera.scanText") private var scanText = true
    @AppStorage("native.gps.enabled") private var gpsEnabled = false
    @AppStorage("native.stamp.enabled") private var stampEnabled = true
    @AppStorage("native.map.enabled") private var mapEnabled = false
    @AppStorage("native.address.enabled") private var addressEnabled = true
    @AppStorage("native.address.autoPreviewMigrated") private var addressPreviewMigrated = false
    @AppStorage("native.pressure.enabled") private var pressureEnabled = false
    @AppStorage("native.photos.enabled") private var saveToPhotos = true
    @StateObject private var archiveAccounts = CloudArchiveAccounts.shared
    @AppStorage("native.archive.keepLocal") private var keepArchiveLocal = true
    @State private var archiveStatus = CloudArchiveDelivery.Summary()
    @State private var archiveNotice: String?
    @State private var connectingArchive = false
    @State private var lastCloudAttempt = Date.distantPast
    @State private var localCloudPendingCount = 0
    @State private var localCloudNeedsAttention = false
    @State private var cloudStatusGeneration = 0
    @AppStorage("native.stamp.size") private var stampSize = "regular"
    @AppStorage("native.stamp.position") private var stampPosition = "bottom"
    @AppStorage("native.stamp.horizontal") private var stampHorizontal = "auto"
    @AppStorage("native.stamp.dateFormat") private var dateFormat = "numeric"
    @AppStorage("native.stamp.font") private var stampFont = "system"
    @AppStorage("native.logo.corner") private var logoCorner = "auto"
    @AppStorage("native.map.scale") private var mapScale = "medium"
    @AppStorage("native.map.corner") private var mapCorner = "auto"
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
    @State private var showAspectPanel = false
    @State private var flashNotice: String?
    @State private var flashNoticeTask: Task<Void, Never>?
    @State private var selectedRecognizedText: RecognizedTextSelection?
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
    @State private var galleryThumbnail: UIImage?
    @State private var galleryThumbnailRevision = UUID()
    @State private var galleryThumbnailFrame: CGRect = .zero
    @State private var wordmarkBottom: CGFloat = 0
    @State private var shutterTop: CGFloat = 0
    @State private var photoFlight: PhotoFlight?
    @State private var photoLanded = false
    @State private var shutterOpacity = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PhotoFlight: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    @State private var showingZoomDial = false
    @State private var zoomDismissTask: Task<Void, Never>?
    @State private var zoomPresetDragStart: CGFloat?
    @State private var suppressZoomPresetTap = false
    @State private var quickRecording = false
    @State private var quickRecordingLocked = false
    @State private var quickZoomStart: CGFloat = 1
    @State private var quickReleasePending = false
    @State private var suppressQuickPhoto = false
    @Environment(\.scenePhase) private var scenePhase

    private var cameraHeader: some View {
        Group {
            if let start = camera.recordingStartedAt {
                TimelineView(.animation(minimumInterval: 0.25)) { _ in
                    let elapsed = CaptureMotion.elapsedSeconds(from: start, to: .now)
                    Text(CaptureMotion.timerLabel(seconds: elapsed))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.red, in: Capsule())
                        .accessibilityLabel("Gravando, \(elapsed) segundos")
                }.padding(.top, 8)
            } else {
                normalCameraHeader
            }
        }
    }

    private var normalCameraHeader: some View {
        VStack(spacing: 0) {
                    MomentraWordmark()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named("MomentraCamera")).maxY
                        } action: { wordmarkBottom = $0 }
                        .padding(.vertical, 4)
                    HStack {
                        Button { cycleFlash() } label: {
                            Image(systemName: camera.flashMode == .off ? "bolt.slash.fill" : camera.flashMode == .auto ? "bolt.badge.a" : "bolt.fill")
                                .font(.title2).foregroundStyle(camera.flashMode == .off ? Color.white : Color.yellow)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(mode == .video || !camera.hasFlash || camera.isCapturing || camera.isSwitching || countdown > 0)
                        .accessibilityLabel("Flash")
                        .accessibilityValue(camera.flashMode == .off ? "Desativado" : camera.flashMode == .auto ? "Automático" : "Ativado")
                        Spacer(minLength: 0)
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
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { showAspectPanel.toggle() }
                        } label: {
                            Text(photoAspect).font(.caption.bold()).frame(width: 44, height: 44)
                        }
                        .disabled(mode == .video || countdown > 0 || camera.isCapturing || camera.isSwitching)
                        .accessibilityLabel("Proporção da foto")
                        Spacer(minLength: 0)
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title2)
                                .frame(width: 44, height: 44)
                                .overlay(alignment: .topTrailing) {
                                    if updates.availableVersion != nil {
                                        Circle().fill(.red).frame(width: 10, height: 10).padding(3)
                                    }
                                }
                        }.accessibilityLabel(updates.availableVersion == nil ? "Configurações" : "Configurações, atualização disponível").disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
                    }.padding(.horizontal, 28).padding(.bottom, 6)
                    if let flashNotice {
                        Text(flashNotice)
                            .font(.caption.weight(.medium)).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(camera.flashMode == .off ? Color.white : Color.yellow, in: RoundedRectangle(cornerRadius: 6))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    if let version = updates.availableVersion {
                        Button("Atualização \(version) disponível") { showSettings = true }
                            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.75), in: Capsule())
                            .disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
                    }
        }
    }

    private var cameraContent: some View {
        GeometryReader { geometry in
            let previewFrame = mode == .photo && !camera.isRecording
                ? (PhotoAspect(rawValue: photoAspect) ?? .standard)
                    .previewFrame(in: geometry.size, top: wordmarkBottom, bottom: shutterTop)
                : CGRect(origin: .zero, size: geometry.size)
            ZStack {
                Color.black.ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { dismissZoomDial() }
                CameraPreview(session: camera.session, device: camera.activeDevice, onCaptureRotation: camera.updateCaptureRotation)
                    .frame(width: previewFrame.width, height: previewFrame.height)
                    .clipped().contentShape(Rectangle())
                    .onTapGesture { dismissZoomDial() }
                    .overlay {
                        if mode == .photo && !camera.isRecording && stampEnabled && stampProfiles.selected.layout.mode == .separate {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                SeparateLiveStamp(snapshot: makeSnapshot(at: timeline.date))
                            }
                        }
                    }
                    .position(x: previewFrame.midX, y: previewFrame.midY)
                    .animation(.easeInOut(duration: 0.2), value: photoAspect)
                if showGrid {
                    CameraGrid().frame(width: previewFrame.width, height: previewFrame.height)
                        .position(x: previewFrame.midX, y: previewFrame.midY)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    cameraHeader
                    if camera.processingVideos > 0 && !camera.isRecording {
                        Text(camera.processingVideos == 1 ? "Aplicando carimbo ao vídeo…" : "Aplicando carimbo a \(camera.processingVideos) vídeos…")
                            .font(.caption).padding(8).background(.black.opacity(0.65), in: Capsule())
                    }
                    if !camera.isRecording, archiveStatus.pending > 0 {
                        Text(archiveStatus.needsAttention ? "Envios pendentes. Confira Armazenamento e contas."
                             : "\(archiveStatus.pending) captura(s) aguardando envio")
                            .font(.caption).padding(8).background(.black.opacity(0.75), in: Capsule())
                    }
                    if mode == .photo && !camera.isRecording && stampEnabled && stampProfiles.selected.layout.mode == .combined && stampProfiles.selected.layout.position == "top" { liveStamp }
                    Spacer(minLength: 8)
                    if countdown > 0 {
                        Text("\(countdown)").font(.system(size: 56, weight: .bold, design: .rounded))
                            .shadow(radius: 6).accessibilityLabel("\(countdown) segundos")
                        Spacer(minLength: 8)
                    }
                    if mode == .photo && !camera.isRecording && stampEnabled && stampProfiles.selected.layout.mode == .combined && stampProfiles.selected.layout.position != "top" && !showingZoomDial { liveStamp }
                    if !camera.isRecording {
                        LiveRecognitionBanner(engine: camera.recognition) { text in
                            selectedRecognizedText = RecognizedTextSelection(text: text)
                        }
                    }
                    VStack(spacing: 0) {
                    Group {
                    if showingZoomDial {
                        ZoomDialView(value: camera.zoomFactor, range: camera.zoomRange, presets: camera.zoomOptions, setZoom: camera.setZoom, editingChanged: zoomEditingChanged)
                            .frame(height: 132).transition(.move(edge: .bottom))
                    } else if !camera.zoomOptions.isEmpty {
                        HStack(spacing: 0) {
                            if camera.isRecording && !camera.zoomOptions.contains(where: { abs($0 - camera.zoomFactor) < 0.01 }) {
                                Text(String(format: "%.1f×", Double(camera.zoomFactor)).replacingOccurrences(of: ".", with: ","))
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.yellow)
                                    .frame(width: 48, height: 44)
                                    .background(Color.black.opacity(0.58), in: Circle())
                            }
                            ForEach(camera.zoomOptions, id: \.self) { factor in
                                Button {
                                    guard !suppressZoomPresetTap else { return }
                                    camera.setZoom(factor)
                                    withAnimation(.easeOut(duration: 0.2)) { showingZoomDial = true }
                                    scheduleZoomDismiss()
                                } label: {
                                    let selected = abs(camera.zoomFactor - factor) < 0.01
                                    Text(factor == 0.5 ? "0,5" : "\(Int(factor))\(selected ? "×" : "")")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(selected ? Color.yellow : Color.white)
                                        .frame(width: 48, height: 44)
                                        .background(selected ? Color.black.opacity(0.58) : Color.clear, in: Circle())
                                }.accessibilityLabel("Zoom \(factor == 0.5 ? "meio" : String(Int(factor))) vezes")
                            }
                        }.padding(.bottom, 8)
                    }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { gesture in
                                guard zoomPresetDragStart != nil || !showingZoomDial else { return }
                                if zoomPresetDragStart == nil {
                                    zoomPresetDragStart = camera.zoomFactor
                                    suppressZoomPresetTap = true
                                    zoomEditingChanged(true)
                                    withAnimation(.easeOut(duration: 0.2)) { showingZoomDial = true }
                                }
                                let start = zoomPresetDragStart ?? camera.zoomFactor
                                camera.setZoom(min(camera.zoomRange.upperBound, max(camera.zoomRange.lowerBound,
                                    start * exp(gesture.translation.width / 150))))
                            }
                            .onEnded { _ in
                                guard zoomPresetDragStart != nil else { return }
                                zoomPresetDragStart = nil; zoomEditingChanged(false)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { suppressZoomPresetTap = false }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { phase in
                                switch phase {
                                case .first(true), .second(true, nil):
                                    guard zoomPresetDragStart == nil, !showingZoomDial else { return }
                                    zoomPresetDragStart = camera.zoomFactor; suppressZoomPresetTap = true; zoomEditingChanged(true)
                                    withAnimation(.easeOut(duration: 0.2)) { showingZoomDial = true }
                                case .second(true, let drag?):
                                    guard let start = zoomPresetDragStart else { return }
                                    camera.setZoom(min(camera.zoomRange.upperBound, max(camera.zoomRange.lowerBound,
                                        start * exp(drag.translation.width / 150))))
                                default: break
                                }
                            }
                            .onEnded { _ in
                                guard zoomPresetDragStart != nil else { return }
                                zoomPresetDragStart = nil; zoomEditingChanged(false)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { suppressZoomPresetTap = false }
                            }
                    )
                    HStack {
                        Menu {
                            ForEach(stampProfiles.profiles) { item in
                                Button(item.name.isEmpty ? "Sem nome" : item.name) { stampProfiles.select(item.id) }
                            }
                        } label: {
                            Image(systemName: "square.on.square").font(.title2)
                                .frame(width: 54, height: 54)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Escolher perfil do carimbo")
                        .opacity(camera.isRecording ? 0 : 1)
                        Spacer(minLength: 0)
                        Button {
                            guard !suppressQuickPhoto else { return }
                            if camera.isRecording && (mode == .video || quickRecordingLocked) {
                                camera.stopRecording(); quickRecording = false; quickRecordingLocked = false
                            } else if mode == .video {
                                startVideoRecording()
                            } else {
                                if countdown > 0 { cancelCountdown() } else { schedulePhoto() }
                            }
                        } label: {
                            let diameter = min(94, geometry.size.width * 0.25)
                            let controlSize = camera.isRecording ? diameter * 0.42 : diameter - 14
                            RoundedRectangle(cornerRadius: camera.isRecording ? controlSize * 0.22 : controlSize / 2)
                                .fill(mode == .video || camera.isRecording ? .red : .white)
                                .frame(width: controlSize, height: controlSize)
                                .frame(width: diameter, height: diameter)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.frame(in: .named("MomentraCamera")).minY
                                } action: { shutterTop = $0 - 1.5 }
                                .contentShape(Circle())
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: camera.isRecording)
                        }
                        .disabled(!camera.ready || camera.isCapturing || camera.isSwitching || (camera.isFinishingRecording && !quickRecording))
                        .accessibilityLabel(countdown > 0 ? "Cancelar temporizador" : camera.isRecording ? "Parar gravação" : mode == .photo ? "Fotografar" : "Gravar vídeo")
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5, maximumDistance: 40)
                                .sequenced(before: DragGesture(minimumDistance: 0))
                                .onChanged { phase in
                                    guard case let .second(true, drag) = phase, mode == .photo else { return }
                                    if !quickRecording {
                                        guard countdown == 0, camera.ready, camera.videoAvailable,
                                              !camera.isCapturing, !camera.isRecording, !camera.isFinishingRecording else { return }
                                        suppressQuickPhoto = true; quickRecording = true; quickReleasePending = false
                                        quickRecordingLocked = false; quickZoomStart = camera.zoomFactor
                                        dismissZoomDial()
                                        startVideoRecording()
                                    }
                                    if let drag {
                                        camera.setZoom(QuickCaptureZoom.value(start: quickZoomStart,
                                            verticalTranslation: drag.translation.height, range: camera.zoomRange))
                                        if drag.translation.width > 100 { quickRecordingLocked = true }
                                    }
                                }
                                .onEnded { _ in
                                    guard quickRecording else { return }
                                    if !quickRecordingLocked {
                                        quickReleasePending = true
                                        if camera.isRecording { camera.stopRecording(); quickRecording = false }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { suppressQuickPhoto = false }
                                }
                        )
                        Spacer(minLength: 0)
                        Button {
                            mapLocation = makeSnapshot(at: Date()).location
                            showMap = true
                        } label: {
                            Image(systemName: "map").font(.title2)
                                .frame(width: 54, height: 54)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Abrir mapa")
                        .opacity(camera.isRecording ? 0 : 1)
                        .overlay {
                            if camera.isRecording && quickRecording {
                                Image(systemName: quickRecordingLocked ? "lock.fill" : "lock.open.fill")
                                    .font(.title3).foregroundStyle(.white.opacity(0.7))
                                    .accessibilityLabel(quickRecordingLocked ? "Gravação bloqueada" : "Deslize à direita para bloquear")
                            }
                        }
                    }.padding(.horizontal, max(28, geometry.size.width * 0.08)).padding(.bottom, 16)
                    }
                    .background {
                        if showingZoomDial {
                            ZoomDialBackdrop().allowsHitTesting(false)
                                .transition(.move(edge: .bottom))
                        }
                    }
                    if camera.isRecording {
                        Color.black.frame(height: 84)
                    } else if showAspectPanel {
                        Color.clear.frame(height: 190)
                    } else {
                    HStack(spacing: 10) {
                        Button { showOriginals = true } label: {
                            Group {
                                if let galleryThumbnail {
                                    Image(uiImage: galleryThumbnail).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo.on.rectangle").font(.title2)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.white.opacity(0.16))
                                }
                            }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 11))
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named("MomentraCamera"))
                                } action: { galleryThumbnailFrame = $0 }
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Abrir capturas")
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            ForEach(CaptureMode.allCases.reversed(), id: \.self) { value in
                                Button { mode = value } label: {
                                    Text(value.rawValue).font(.subheadline.weight(.medium))
                                        .foregroundStyle(mode == value ? Color.yellow : Color.white)
                                        .frame(maxWidth: .infinity).frame(height: 42)
                                        .background(mode == value ? Color.white.opacity(0.12) : Color.clear, in: Capsule())
                                }
                                .disabled((value == .video && !camera.videoAvailable) || camera.isRecording || camera.isFinishingRecording || camera.isCapturing || camera.isSwitching || countdown > 0)
                                .accessibilityAddTraits(mode == value ? .isSelected : [])
                            }
                        }.padding(3).background(.white.opacity(0.10), in: Capsule()).frame(maxWidth: 220)
                        Spacer(minLength: 0)
                        Button { camera.flipCamera() } label: {
                            Image(systemName: "camera.rotate").font(.title2).frame(width: 52, height: 52)
                                .background(.white.opacity(0.10), in: Circle())
                        }
                        .disabled(!camera.ready || camera.isCapturing || camera.isSwitching || camera.isRecording || camera.isFinishingRecording || countdown > 0)
                        .accessibilityLabel("Trocar câmera")
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
                    .background(Color.black)
                    }
                }.foregroundStyle(.white)
                if showAspectPanel && !camera.isRecording {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) { showAspectPanel = false }
                        }
                        .overlay(alignment: .bottom) {
                            PhotoAspectPanel(selection: $photoAspect) {
                                withAnimation(.easeInOut(duration: 0.22)) { showAspectPanel = false }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                }
                if let flight = photoFlight {
                    let frame = CaptureMotion.aspectFit(flight.image.size,
                                                        in: photoLanded ? galleryThumbnailFrame : previewFrame)
                    Image(uiImage: flight.image).resizable()
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: photoLanded ? 8 : 0))
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                Rectangle().fill(.black.opacity(shutterOpacity))
                    .frame(width: previewFrame.width, height: previewFrame.height)
                    .position(x: previewFrame.midX, y: previewFrame.midY)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .coordinateSpace(name: "MomentraCamera")
            .task(id: photoFlight?.id) {
                guard let flight = photoFlight else { return }
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                guard photoFlight?.id == flight.id else { return }
                withAnimation(.easeOut(duration: 0.12)) { shutterOpacity = 0 }
                withAnimation(.easeInOut(duration: 0.34), completionCriteria: .logicallyComplete) {
                    photoLanded = true
                } completion: {
                    guard photoFlight?.id == flight.id else { return }
                    finishPhotoFlight()
                }
            }
        }
    }

    private var observedCamera: some View {
        cameraContent
        .statusBarHidden()
        .modifier(CameraHardwareCaptureModifier(enabled: scenePhase == .active && !showSettings && selectedRecognizedText == nil && !showOriginals && !showMap && !showSettingsImport && !showLogoImport && !showForecastTerms && !showGoogleConsent, action: handleHardwareCapture))
        .task { await updates.check() }
        .onAppear { if !addressPreviewMigrated { var layout = stampProfiles.selected.layout; layout.showsAddress = true; stampProfiles.setLayout(layout); addressEnabled = true; addressPreviewMigrated = true }; refreshGalleryThumbnail(); camera.recognition.setEnabled(qr: scanQR, text: scanText); camera.start(); location.setEnabled(gpsEnabled); pressure.setEnabled(true); refreshLogo(); refreshAddress(); publishCaptureContext() }
        .onDisappear { finishPhotoFlight(); flashNoticeTask?.cancel(); zoomDismissTask?.cancel(); cancelCountdown(); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel(); addressPreview.clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start(); location.setEnabled(gpsEnabled); pressure.setEnabled(true); refreshAddress(); retryCloudCaptures(); Task { await updates.check() } }
            else { finishPhotoFlight(); CloudBackgroundScheduler.scheduleIfNeeded(); cancelCountdown(); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel(); addressPreview.clear() }
        }
    }

    private var locationObservedCamera: some View {
        observedCamera
        .onReceive(location.$location) { fix in addressPreview.update(location: fix, enabled: canPreviewAddress) }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            if canPreviewAddress { refreshAddress() }
            if scenePhase == .active && Date().timeIntervalSince(lastCloudAttempt) >= 30 { retryCloudCaptures() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .momentraCloudCaptureStaged).receive(on: RunLoop.main)) { _ in
            retryCloudCaptures()
        }
        .onReceive(googlePhotos.$pendingCloudCaptures) { _ in
            refreshCloudQueueStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .momentraOpenCamera).receive(on: RunLoop.main)) { _ in
            showSettings = false
            showOriginals = false
            showMap = false
            showSettingsImport = false
            showLogoImport = false
            showForecastTerms = false
            showGoogleConsent = false
            showAspectPanel = false
            selectedRecognizedText = nil
            camera.start()
        }
    }

    private var trackedCamera: some View {
        locationObservedCamera
        .onChange(of: scanQR) { _, enabled in camera.recognition.setEnabled(qr: enabled, text: scanText) }
        .onChange(of: scanText) { _, enabled in camera.recognition.setEnabled(qr: scanQR, text: enabled) }
        .onChange(of: gpsEnabled) { _, enabled in location.setEnabled(enabled); refreshAddress() }
        .onChange(of: stampProfiles.selected.layout.showsAddress) { _, _ in refreshAddress() }
        .onChange(of: stampEnabled) { _, _ in refreshAddress() }
        .onChange(of: mode) { _, _ in refreshAddress() }
        .onChange(of: showSettings) { _, _ in refreshAddress() }
        .onChange(of: showOriginals) { _, showing in refreshAddress(); if !showing { refreshGalleryThumbnail() } }
        .onChange(of: camera.isRecording) { _, recording in
            if recording {
                if quickRecording && quickReleasePending && !quickRecordingLocked {
                    camera.stopRecording(); quickRecording = false
                }
            } else {
                quickRecordingLocked = false
            }
        }
        .onChange(of: camera.isFinishingRecording) { _, finishing in
            if !finishing && !camera.isRecording && quickRecording {
                quickRecording = false; quickRecordingLocked = false; quickReleasePending = false
                suppressQuickPhoto = false
            }
        }
        .onReceive(camera.completedPhoto) { showCapturedPhoto($0) }
        .onChange(of: reduceMotion) { _, enabled in if enabled { finishPhotoFlight() } }
    }

    private var moreTrackedCamera: some View {
        trackedCamera
        .onChange(of: showMap) { _, _ in refreshAddress() }
        .onChange(of: stampProfiles.selectedID) { _, _ in refreshLogo(); refreshAddress(); publishCaptureContext() }
        .onChange(of: stampProfiles.selected.logoName) { _, _ in refreshLogo() }
        .onChange(of: stampProfiles.selected.layout) { _, _ in publishCaptureContext() }
        .onChange(of: stampProfiles.selected.name) { _, _ in publishCaptureContext() }
        .onChange(of: stampProfiles.selected.note) { _, _ in publishCaptureContext() }
        .onChange(of: keepArchiveLocal) { _, _ in publishCaptureContext() }
        .onChange(of: archiveAccounts.accounts.map { $0.enabled ? $0.id : nil }) { _, _ in
            publishCaptureContext()
            retryCloudCaptures()
        }
        .onChange(of: showSettings) { _, showing in if !showing { publishCaptureContext() } }
        .onChange(of: selectedLogo) { _, item in
            guard let item else { return }
            let targetProfile = stampProfiles.selectedID
            logoLoading = true
            Task { @MainActor in
                defer { logoLoading = false; selectedLogo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ProfileLogoStore.LogoError.invalid }
                    let name = try await Task.detached(priority: .utility) { try ProfileLogoStore.save(data) }.value
                    setLogo(name, for: targetProfile)
                    if stampProfiles.selectedID == targetProfile { refreshLogo() }
                } catch {
                    importMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar o logotipo. A imagem anterior foi preservada."
                }
            }
        }
    }

    var body: some View {
        moreTrackedCamera
        .sheet(item: $selectedRecognizedText) { item in RecognizedTextSheet(text: item.text) }
        .sheet(isPresented: $showOriginals) { OriginalsView(googlePhotos: googlePhotos, stampProfiles: stampProfiles) }
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
        .sheet(isPresented: $showSettings) { settingsSheet }
        .alert("Momentra", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.clearError() } })) {
            Button("OK") { camera.clearError() }
        } message: { Text(camera.errorMessage ?? "") }
    }

    private var settingsSheet: some View {
            NavigationStack {
                Form {
                    Section("Atualizações") {
                        if let version = updates.availableVersion {
                            Text("Nova versão disponível: \(version)").font(.headline)
                            if directUpdate.ready {
                                Button("Atualizar agora") {
                                    Task {
                                        await directUpdate.install(expectedVersion: version) {
                                            UpdateCloseReadiness.allowsClose(capturing: camera.isCapturing, switching: camera.isSwitching,
                                                recording: camera.isRecording, finishing: camera.isFinishingRecording,
                                                processingVideos: camera.processingVideos, cloudBusy: googlePhotos.busy)
                                        }
                                    }
                                }
                                    .disabled(directUpdate.busy)
                            } else {
                                Text("Para atualizar diretamente, ative uma vez pelo link pessoal de instalação.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Link("Ver instruções", destination: UpdateService.releasesURL)
                            }
                        }
                        Button(updates.checking ? "Verificando…" : "Buscar atualizações") {
                            Task { await updates.check(force: true) }
                        }.disabled(updates.checking)
                        if let status = updates.status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        if let message = directUpdate.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Conta Google") {
                        HStack(spacing: 12) {
                            GoogleAccountMark().frame(width: 48, height: 48)
                                .clipShape(Circle()).accessibilityHidden(true)
                            LabeledContent("Conta", value: GIDSignIn.sharedInstance.currentUser?.profile?.email ?? "Não conectada")
                        }
                        if !googlePhotos.connected && googlePhotos.configured {
                            GoogleWelcomeButton { showGoogleConsent = true }.frame(height: 48).disabled(googlePhotos.busy)
                        } else if googlePhotos.connected {
                            Text("Google Fotos conectado").foregroundStyle(.secondary)
                        }
                    }
                    Section("Ajustes da câmera") {
                        NavigationLink("Estilos fotográficos") { PhotoStylesView(selected: $photoStyle) }
                        Toggle("Escanear QR Codes", isOn: $scanQR)
                        Toggle("Mostrar Texto Detectado", isOn: $scanText)
                        Text("QR Codes e textos são reconhecidos automaticamente na prévia. Toque no resultado para abrir ou selecionar.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !camera.recognition.available {
                            Text("A leitura automática não está disponível com a configuração atual da câmera.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Composição") {
                        Toggle("Grade", isOn: $showGrid)
                    }
                    Section("Aparência") {
                        NavigationLink("Ícone do aplicativo") { AppIconPicker() }
                    }
                    Section("Carimbo") {
                        NavigationLink("Layout e perfis") {
                            StampLayoutEditor(store: stampProfiles, selectedLogo: $selectedLogo, logoLoading: logoLoading,
                                              importLogo: { showLogoImport = true })
                        }
                        if stampProfiles.profiles.count > 1 {
                            Picker("Perfil ao abrir o app", selection: Binding(
                                get: { stampProfiles.startupSelection },
                                set: { stampProfiles.setStartup($0) }
                            )) {
                                Text("Usado por último").tag("last")
                                ForEach(stampProfiles.profiles) { item in
                                    Text(item.name.isEmpty ? "Sem nome" : item.name).tag(item.id.uuidString)
                                }
                            }
                        }
                    }
                    Toggle("Localização", isOn: $gpsEnabled)
                    Toggle("Carimbo", isOn: $stampEnabled)
                    Toggle("Copiar para o app Fotos", isOn: $saveToPhotos)
                        .disabled(!effectiveLocalStorage)
                    Text(effectiveLocalStorage
                         ? "Adiciona uma cópia à biblioteca Fotos do iPhone. A opção de armazenamento abaixo define onde o Momentra guarda as capturas."
                         : "No modo somente nuvem, novas fotos não são copiadas para o app Fotos do iPhone.")
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
                    Section("Armazenamento e contas") {
                        Toggle("Armazenamento local", isOn: $keepArchiveLocal)
                            .disabled(keepArchiveLocal && archiveDestinations.isEmpty)
                        ForEach(archiveAccounts.accounts, id: \.id) { account in
                            Toggle(isOn: Binding(get: { account.enabled }, set: { enabled in
                                if !enabled && !keepArchiveLocal && archiveDestinations.count == 1 { keepArchiveLocal = true }
                                do { try archiveAccounts.setEnabled(enabled, for: account.id) }
                                catch { archiveNotice = "Não foi possível alterar o destino." }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(account.id.provider == .googleDrive ? "Google Drive" : "OneDrive")
                                    Text(account.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Adicionar conta Google Drive") { connectArchive(.googleDrive) }.disabled(connectingArchive)
                        Button("Adicionar conta OneDrive") { connectArchive(.oneDrive) }.disabled(connectingArchive)
                        Text("Cada captura usa os destinos ativos no disparo. Sem conexão, o original e a versão processada ficam no iPhone. Os envios são retomados ao abrir o app ou quando o iOS permitir.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if archiveStatus.pending > 0 {
                            Text("\(archiveStatus.pending) captura(s) aguardando envio").font(.footnote)
                        }
                        if archiveStatus.needsAttention {
                            Text("Há envios que precisam de atenção. Confira as contas, a conexão e o espaço disponível. Os arquivos pendentes ficam no iPhone.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        ForEach(archiveStatus.issues, id: \.self) { issue in
                            Text(issue).font(.footnote).foregroundStyle(.orange)
                        }
                        if let archiveNotice { Text(archiveNotice).font(.footnote) }
                    }
                    Section("Google Fotos · arquivo anterior") {
                        if googlePhotos.configured {
                            if googlePhotos.connected {
                                Button("Desconectar conta") { googlePhotos.signOut() }.disabled(googlePhotos.busy)
                            } else {
                                Button("Conectar Google Fotos") { showGoogleConsent = true }.disabled(googlePhotos.busy)
                            }
                            Text(localCloudPendingCount > 0
                                 ? "\(localCloudPendingCount) captura(s) da fila anterior preservada(s)."
                                 : "Use a conta anterior para consultar a galeria do Google Fotos.")
                                .font(.footnote)
                            if localCloudNeedsAttention {
                                Text("Há envios antigos com confirmação pendente.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            Text("A fila anterior permanece no aparelho. Novas fotos usam os destinos acima.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("A conexão nativa ainda não está configurada.").font(.footnote).foregroundStyle(.secondary)
                        }
                        if let message = googlePhotos.message { Text(message).font(.footnote) }
                    }
                    Section {
                        LabeledContent("Versão instalada", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Indisponível")
                    } header: {
                        Text("Sobre")
                    } footer: {
                        Text("Desenvolvido por Marcos Rodrigues Pires · 2026")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
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
                    let targetProfile = stampProfiles.selectedID
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
                            if stampProfiles.selectedID == targetProfile { refreshLogo() }
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
                        importMessage = "Ajustes compatíveis importados. Os logotipos devem ser importados separadamente; confira as posições na foto."
                    } catch {
                        importMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível importar o arquivo. Nenhuma configuração foi alterada."
                    }
                }
                .alert("Momentra", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                    Button("OK") { importMessage = nil }
                } message: { Text(importMessage ?? "") }
            }
    }

    private func zoomEditingChanged(_ editing: Bool) {
        zoomDismissTask?.cancel()
        if !editing { scheduleZoomDismiss() }
    }

    private func scheduleZoomDismiss() {
        zoomDismissTask?.cancel()
        zoomDismissTask = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) { showingZoomDial = false }
        }
    }

    private func dismissZoomDial() {
        guard showingZoomDial else { return }
        zoomDismissTask?.cancel()
        zoomPresetDragStart = nil
        suppressZoomPresetTap = false
        withAnimation(.easeIn(duration: 0.22)) { showingZoomDial = false }
    }

    private func cycleFlash() {
        let next = FlashCycle.next(current: camera.flashMode, supported: camera.availableFlashModes)
        camera.flashMode = next
        let label = next == .on ? "FLASH ATIVADO" : next == .auto ? "FLASH AUTOMÁTICO" : "FLASH DESATIVADO"
        flashNoticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { flashNotice = label }
        flashNoticeTask = Task {
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { flashNotice = nil }
        }
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

    private func startVideoRecording() {
        let snapshot = stampEnabled ? makeSnapshot(at: Date()) : nil
        let profile = CaptureProfileTag(id: stampProfiles.selected.id, name: stampProfiles.selected.name)
        camera.startRecording(saveToPhotos: saveToPhotos, snapshot: snapshot, profile: profile)
    }

    private func capturePhoto() {
        let snapshot = stampEnabled ? makeSnapshot(at: Date()) : nil
        camera.capture(snapshot: snapshot, aspect: PhotoAspect(rawValue: photoAspect) ?? .standard,
                       saveToPhotos: effectiveLocalStorage && saveToPhotos,
                       style: MomentraPhotoStyle(rawValue: photoStyle) ?? .natural,
                       profile: CaptureProfileTag(id: stampProfiles.selected.id, name: stampProfiles.selected.name),
                       archivePlan: currentArchivePlan)
    }

    private var archiveDestinations: [CloudDeliveryPlan.Destination] {
        archiveAccounts.accounts.filter(\.enabled).map(\.id)
    }

    private var effectiveLocalStorage: Bool { keepArchiveLocal || archiveDestinations.isEmpty }

    private var currentArchivePlan: CloudDeliveryPlan? {
        CloudDeliveryPlan(keepLocal: effectiveLocalStorage, destinations: archiveDestinations)
    }

    private func connectArchive(_ provider: CloudDeliveryPlan.Provider) {
        guard let window = Self.presentingController()?.view.window else {
            archiveNotice = "Não foi possível abrir a autenticação."
            return
        }
        connectingArchive = true
        archiveNotice = nil
        Task {
            defer { connectingArchive = false }
            do { try await archiveAccounts.connect(provider, presenting: window) }
            catch { archiveNotice = error.localizedDescription }
        }
    }

    private func retryCloudCaptures() {
        lastCloudAttempt = Date()
        refreshCloudQueueStatus()
        guard scenePhase == .active else { return }
        Task {
            if let status = await CloudArchiveDelivery.shared.drain() { archiveStatus = status }
        }
    }

    private func refreshCloudQueueStatus() {
        cloudStatusGeneration &+= 1
        let generation = cloudStatusGeneration
        Task {
            let status = await Task.detached(priority: .utility) { () -> (Int, Bool)? in
                guard let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                               appropriateFor: nil, create: false),
                      let entries = try? CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
                        .allEntries() else { return nil }
                return (entries.filter { $0.phase != .cleaned }.count, entries.contains { $0.phase == .uncertain })
            }.value
            guard cloudStatusGeneration == generation, let status else { return }
            localCloudPendingCount = status.0
            localCloudNeedsAttention = status.1
        }
    }

    private func showCapturedPhoto(_ image: UIImage) {
        finishPhotoFlight()
        galleryThumbnailRevision = UUID()
        guard scenePhase == .active, !showSettings, !showOriginals, !showAspectPanel,
              !reduceMotion, !galleryThumbnailFrame.isEmpty else {
            galleryThumbnail = image
            return
        }
        shutterOpacity = 0.35
        photoFlight = PhotoFlight(image: image)
    }

    private func finishPhotoFlight() {
        if let flight = photoFlight { galleryThumbnail = flight.image }
        photoFlight = nil
        photoLanded = false
        shutterOpacity = 0
    }

    private func refreshGalleryThumbnail() {
        let revision = UUID()
        galleryThumbnailRevision = revision
        Task {
            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
                      let files = try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Processed", isDirectory: true), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]),
                      let newest = files.max(by: { left, right in
                          let lhs = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                          let rhs = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                          return lhs < rhs
                      }),
                      let source = CGImageSourceCreateWithURL(newest as CFURL, nil),
                      let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) else { return nil }
                return UIImage(cgImage: thumb)
            }.value
            if galleryThumbnailRevision == revision, photoFlight == nil { galleryThumbnail = image }
        }
    }

    private var liveStamp: some View {
        HStack(spacing: 0) {
            if stampProfiles.selected.layout.horizontal == "right" { Spacer(minLength: 0) }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LiveStampView(snapshot: makeSnapshot(at: timeline.date))
            }.frame(maxWidth: stampProfiles.selected.layout.horizontal == "auto" ? .infinity : 280)
            if stampProfiles.selected.layout.horizontal == "left" { Spacer(minLength: 0) }
        }.padding(.horizontal, 16)
            .padding(.top, stampProfiles.selected.layout.position == "top" ? 12 : 0)
            .padding(.bottom, stampProfiles.selected.layout.position == "top" ? 0 : 12)
    }

    private static func presentingController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private func makeSnapshot(at date: Date) -> StampSnapshot {
        StampSnapshot(capturedAt: date, gpsEnabled: gpsEnabled,
            mapEnabled: stampProfiles.selected.layout.showsMap, addressEnabled: stampProfiles.selected.layout.showsAddress,
            cachedAddress: addressPreview.current(for: location.location, at: date), title: "", note: stampProfiles.selected.note,
            logo: logo, logoCorner: "auto", compact: stampProfiles.selected.layout.compact,
            position: stampProfiles.selected.layout.position, horizontal: stampProfiles.selected.layout.horizontal,
            longDate: stampProfiles.selected.layout.dateFormat == "long", fontStyle: stampProfiles.selected.layout.fontStyle,
            mapScale: stampProfiles.selected.layout.mapScale, mapCorner: "auto",
            pressure: pressure.sample, forecast: gpsEnabled ? weather.current(location: location.location, at: date) : nil,
            location: location.location, heading: location.heading, layout: stampProfiles.selected.layout)
    }

    private func publishCaptureContext() {
        guard #available(iOS 18.0, *) else { return }
        let context = MomentraCaptureContext(stampEnabled: stampEnabled, gpsEnabled: gpsEnabled,
            title: "", note: LockedCaptureMetadata.safeNote(stampProfiles.selected.note),
            compact: stampProfiles.selected.layout.compact, position: stampProfiles.selected.layout.position,
            horizontal: stampProfiles.selected.layout.horizontal, longDate: stampProfiles.selected.layout.dateFormat == "long",
            fontStyle: stampProfiles.selected.layout.fontStyle, aspect: photoAspect,
            saveToPhotos: effectiveLocalStorage && saveToPhotos,
            profileID: stampProfiles.selected.id, profileName: LockedCaptureMetadata.safeProfileName(stampProfiles.selected.name),
            cloudOwnerHash: nil,
            layoutData: (try? JSONEncoder().encode(stampProfiles.selected.layout)).flatMap { $0.count <= 2000 ? $0 : nil },
            hasLogo: !stampProfiles.selected.logoName.isEmpty,
            archivePlan: currentArchivePlan)
        Task { try? await MomentraCaptureIntent.updateAppContext(context) }
    }

    private func handleHardwareCapture() {
        guard camera.ready, !camera.isCapturing, !camera.isSwitching, !camera.isFinishingRecording else { return }
        if mode == .video {
            if camera.isRecording { camera.stopRecording() } else { startVideoRecording() }
        } else if countdown > 0 {
            cancelCountdown()
        } else {
            schedulePhoto()
        }
    }

    private var canPreviewAddress: Bool {
        scenePhase == .active && gpsEnabled && stampEnabled && stampProfiles.selected.layout.showsAddress
    }

    private func refreshAddress() { addressPreview.update(location: location.location, enabled: canPreviewAddress) }

    private func setLogo(_ name: String, for profileID: UUID) {
        stampProfiles.setLogo(name, for: profileID)
    }

    private func refreshLogo() { logo = ProfileLogoStore.load(stampProfiles.selected.logoName) }

    private func apply(_ transfer: SettingsTransfer) {
        let s = transfer.settings
        guard let h = s.profiles["HAMOA"], let p = s.profiles["PIRESCO"], let personal = s.profiles["PESSOAL"] else { return }
        hamoaTitle = h.title; hamoaNote = h.note
        pirescoTitle = p.title; pirescoNote = p.note
        pessoalTitle = personal.title; pessoalNote = personal.note
        profile = s.profile
        let selectedImport = s.profiles[s.profile] ?? h
        stampProfiles.setNote(selectedImport.note)
        stampEnabled = s.stamp; gpsEnabled = s.gps; mapEnabled = s.map
        saveToPhotos = s.allowGallery
        if let size = s.size { stampSize = size }
        if let position = s.position { stampPosition = position }
        if let corner = s.timestampCorner {
            stampPosition = corner.hasPrefix("top-") ? "top" : "bottom"
            stampHorizontal = corner.hasSuffix("-left") ? "left" : "right"
        }
        if let format = s.timestampFormat { dateFormat = format }
        if let font = s.timestampFont { stampFont = font }
        if let scale = s.mapScale { mapScale = scale }
        if let corner = s.mapCorner { mapCorner = corner }
        if let corner = s.logoCorner { logoCorner = corner }
        photoAspect = s.aspectRatio
    }
}

private struct CameraGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for index in 1...2 {
                    let x = geometry.size.width * CGFloat(index) / 3
                    let y = geometry.size.height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }.stroke(.white.opacity(0.5), lineWidth: 0.5)
        }
    }
}

private struct CameraHardwareCaptureModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onCameraCaptureEvent(isEnabled: enabled) { event in
                if event.phase == .ended { action() }
            }
        } else {
            content
        }
    }
}

private struct LiveStampView: View {
    let snapshot: StampSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if snapshot.mapEnabled, let coordinate = snapshot.location?.coordinate {
                Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))), interactionModes: []) {
                    Annotation("Localização", coordinate: coordinate) {
                        Circle().fill(.blue).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                .mapStyle(snapshot.layout.mapStyle == .satellite ? .imagery : .standard)
                .frame(width: (snapshot.mapScale == "small" ? 60 : snapshot.mapScale == "large" ? 100 : 80) * snapshot.layout.mapSize * snapshot.layout.combinedSize,
                       height: (snapshot.mapScale == "small" ? 75 : snapshot.mapScale == "large" ? 125 : 100) * snapshot.layout.mapSize * snapshot.layout.combinedSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id("\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))")
            }
            if snapshot.layout.showsInformation {
            VStack(alignment: snapshot.layout.textAlignment == "right" ? .trailing : snapshot.layout.textAlignment == "center" ? .center : .leading, spacing: 2) {
                ForEach(snapshot.lines, id: \.self) { line in
                    Text(line).font(.system(size: (snapshot.compact ? 10 : 12) * snapshot.layout.informationSize * snapshot.layout.combinedSize, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        .fontDesign(snapshot.fontStyle == "mono" ? .monospaced : snapshot.fontStyle == "serif" ? .serif : .default)
                }
                if snapshot.addressEnabled && snapshot.location != nil {
                    Text(snapshot.cachedAddress ?? "Buscando endereço…").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
            }
            Spacer(minLength: 0)
            if snapshot.layout.showsLogo, let logo = snapshot.logo {
                Image(uiImage: logo).resizable().scaledToFit().frame(width: 38 * snapshot.layout.logoSize * snapshot.layout.combinedSize,
                                                                 height: 38 * snapshot.layout.logoSize * snapshot.layout.combinedSize)
                    .accessibilityLabel("Logotipo do perfil")
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
