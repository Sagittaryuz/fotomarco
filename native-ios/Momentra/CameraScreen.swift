import SwiftUI
import AVFoundation
import AVKit
import MapKit
import UniformTypeIdentifiers
import PhotosUI
import ImageIO
import CoreMotion

enum CameraGallerySwipe {
    static func qualifies(_ translation: CGSize) -> Bool {
        translation.width >= 82 && translation.width > abs(translation.height) * 1.35
    }
}

/// Keeps the stamp upright relative to the phone, even when interface rotation is locked.
enum StampOrientation {
    static func deviceOrientation(gravityX: Double, gravityY: Double) -> UIDeviceOrientation? {
        guard gravityX.isFinite, gravityY.isFinite, hypot(gravityX, gravityY) >= 0.22 else { return nil }
        if abs(gravityX) > abs(gravityY) * 1.15 {
            return gravityX < 0 ? .landscapeLeft : .landscapeRight
        }
        if abs(gravityY) > abs(gravityX) * 1.15 {
            return gravityY < 0 ? .portrait : .portraitUpsideDown
        }
        return nil
    }
    static func angle(device: UIDeviceOrientation, interface: UIInterfaceOrientation) -> Double {
        let deviceAngle: Double
        switch device {
        case .portrait: deviceAngle = 0
        case .portraitUpsideDown: deviceAngle = 180
        case .landscapeLeft: deviceAngle = 90
        case .landscapeRight: deviceAngle = -90
        default: return 0
        }
        let interfaceAngle: Double
        switch interface {
        case .portraitUpsideDown: interfaceAngle = 180
        case .landscapeRight: interfaceAngle = 90
        case .landscapeLeft: interfaceAngle = -90
        default: interfaceAngle = 0
        }
        var result = deviceAngle - interfaceAngle
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

@MainActor
private final class StampMotionOrientation: ObservableObject {
    @Published private(set) var orientation: UIDeviceOrientation = .portrait
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity,
                  let next = StampOrientation.deviceOrientation(gravityX: gravity.x, gravityY: gravity.y) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.orientation != next else { return }
                self.orientation = next
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

private struct StampOrientationContainer<Content: View>: View {
    let deviceOrientation: UIDeviceOrientation
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let angle = StampOrientation.angle(device: deviceOrientation, interface: .portrait)
            let swap = abs(angle) == 90
            content()
                .frame(width: swap ? geometry.size.height : geometry.size.width,
                       height: swap ? geometry.size.width : geometry.size.height)
                .rotationEffect(.degrees(angle))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .animation(.easeInOut(duration: 0.2), value: angle)
        }
    }
}

struct CameraScreen: View {
    private enum CaptureMode: String, CaseIterable { case photo = "FOTO", video = "VÍDEO" }
    @StateObject private var camera = CameraService()
    @StateObject private var stampMotion = StampMotionOrientation()
    @StateObject private var location = LocationService()
    @StateObject private var addressPreview = AddressPreviewService()
    @StateObject private var pressure = PressureService()
    @StateObject private var weather = ForecastService()
    @StateObject private var updates = UpdateService()
    @StateObject private var directUpdate = DirectUpdateAccess.shared
    @StateObject private var stampProfiles = StampProfilesStore()
    @ObservedObject private var businessIdentity = BusinessIdentity.shared
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
    @StateObject private var archiveAccounts = CloudArchiveAccounts.shared
    @AppStorage("native.archive.keepLocal") private var keepArchiveLocal = true
    @AppStorage("native.archive.keepOriginal") private var keepArchiveOriginal = true
    @State private var archiveStatus = CloudArchiveDelivery.Summary()
    @State private var businessArchiveStatus = BusinessArchiveDelivery.Summary()
    @State private var archiveNotice: String?
    @State private var archiveConnectionError: String?
    @State private var connectingArchive = false
    @State private var pendingArchivePolicy: CloudDeliveryPlan?
    @State private var captureContextTask: Task<Bool, Never>?
    @State private var lastCloudAttempt = Date.distantPast
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
    @AppStorage("native.profile.pessoal.title") private var pessoalTitle = "PHOTOMARK"
    @AppStorage("native.profile.pessoal.note") private var pessoalNote = ""
    @AppStorage("native.profile.hamoa.logo") private var hamoaLogo = ""
    @AppStorage("native.profile.piresco.logo") private var pirescoLogo = ""
    @AppStorage("native.profile.pessoal.logo") private var pessoalLogo = ""
    @State private var showAspectPanel = false
    @State private var flashNotice: String?
    @State private var flashNoticeTask: Task<Void, Never>?
    @State private var selectedRecognizedText: RecognizedTextSelection?
    @State private var showSettings = false
    @State private var stampEditorSection: StampLayoutEditor.Element?
    @State private var showOrganizationReadOnly = false
    @State private var businessCaptureNotice: String?
    @State private var showUpdateMessage = false
    @State private var showSupportPanel = false
    @State private var showOriginals = false
    @State private var showMap = false
    @State private var mapAppearance: StampLayout.MapAppearance = .satellite
    @State private var mapLocation: CLLocation?
    @State private var showSettingsImport = false
    @State private var importMessage: String?
    @State private var mode: CaptureMode = .photo
    @State private var modeTransitionBlur = false
    @State private var modeTransitionTask: Task<Void, Never>?
    @State private var lastZoomHaptic = 0.0
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var logo: UIImage?
    @State private var extraLogos: [UIImage?] = []
    @State private var loadedLogoNames: [String] = []
    @State private var galleryThumbnail: CameraService.CapturePreview?
    @State private var sessionCaptures: [CameraService.CapturePreview] = []
    @State private var sessionCaptureCount = 0
    @State private var cameraShareTask: Task<Void, Never>?
    @State private var cameraShare: GalleryShareBatch?
    @State private var cameraShareFailed = false
    @State private var galleryThumbnailRevision = UUID()
    @State private var galleryThumbnailFrame: CGRect = .zero
    @State private var gallerySwipeProgress: CGFloat = 0
    @State private var wordmarkBottom: CGFloat = 0
    @State private var shutterTop: CGFloat = 0
    @State private var shutterCenterX: CGFloat?
    @State private var photoFlight: PhotoFlight?
    @State private var photoLanded = false
    @State private var shutterOpacity = 0.0
    @State private var stampDeviceOrientation: UIDeviceOrientation = .portrait
    @State private var shutterFeedbackTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PhotoFlight: Identifiable {
        let id = UUID()
        let capture: CameraService.CapturePreview
    }
    @State private var pinchZoom: PreviewPinchZoom?
    @State private var showingZoomDial = false
    @State private var zoomDismissTask: Task<Void, Never>?
    @State private var zoomDrag: ContinuousCameraZoom?
    @State private var zoomMotionTask: Task<Void, Never>?
    @GestureState private var zoomTouchActive = false
    @State private var suppressZoomPresetTap = false
    @State private var quickRecording = false
    @State private var quickRecordingLocked = false
    @State private var quickZoomStart: CGFloat = 1
    @State private var quickReleasePending = false
    @State private var suppressQuickPhoto = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var didEnterBackground = false

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
            HStack(spacing: 4) {
                Button { FotomarcoHaptics.play(.buttons); cycleFlash() } label: {
                    Image(systemName: camera.flashMode == .off ? "bolt.slash.fill" : camera.flashMode == .auto ? "bolt.badge.a" : "bolt.fill")
                        .font(.title2).foregroundStyle(camera.flashMode == .off ? Color.white : Color.yellow)
                        .frame(width: 44, height: 44)
                }
                .disabled(mode == .video || !camera.hasFlash || camera.isCapturing || camera.isSwitching || countdown > 0)
                .accessibilityLabel("Flash")
                .accessibilityValue(camera.flashMode == .off ? "Desativado" : camera.flashMode == .auto ? "Automático" : "Ativado")

                Menu {
                    Button("Desligado") { FotomarcoHaptics.play(.buttons); timerSeconds = 0 }
                    Button("3 segundos") { FotomarcoHaptics.play(.buttons); timerSeconds = 3 }
                    Button("10 segundos") { FotomarcoHaptics.play(.buttons); timerSeconds = 10 }
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "timer").font(.title2)
                        if timerSeconds > 0 { Text("\(timerSeconds)s").font(.caption2) }
                    }.frame(width: 44, height: 44)
                }
                .disabled(mode == .video || countdown > 0 || camera.isCapturing || camera.isSwitching)
                .accessibilityLabel("Temporizador")

                Spacer(minLength: 4)
                Button {
                    FotomarcoHaptics.play(.buttons)
                    setSupportPanel(true)
                } label: {
                    MomentraWordmark()
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named("MomentraCamera")).maxY
                        } action: { wordmarkBottom = $0 }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre o painel de apoio ao aplicativo")
                Spacer(minLength: 4)

                Button {
                    FotomarcoHaptics.play(.buttons)
                    withAnimation(.easeInOut(duration: 0.22)) { showAspectPanel.toggle() }
                } label: {
                    Text(photoAspect).font(.system(size: 17, weight: .semibold)).monospacedDigit().frame(width: 44, height: 44)
                }
                .disabled(mode == .video || countdown > 0 || camera.isCapturing || camera.isSwitching)
                .accessibilityLabel("Proporção da foto")

                Button { FotomarcoHaptics.play(.buttons); showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title2)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if updates.availableVersion != nil {
                                Circle().fill(.red).frame(width: 10, height: 10).padding(3)
                            }
                        }
                }
                .accessibilityLabel(updates.availableVersion == nil ? "Configurações" : "Configurações, atualização disponível")
                .disabled(camera.isRecording || camera.isFinishingRecording || countdown > 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)

            if let flashNotice {
                Text(flashNotice)
                    .font(.caption.weight(.medium)).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(camera.flashMode == .off ? Color.white : Color.yellow, in: RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if let version = updates.availableVersion {
                Button {
                    if directUpdate.ready { requestUpdate(version, fromBanner: true) }
                    else { FotomarcoHaptics.play(.buttons); showSettings = true }
                } label: {
                    Text(directUpdate.busy ? "Preparando atualização…" : "Atualização \(version) disponível")
                        .font(.caption.bold()).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(.black.opacity(0.75), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(directUpdate.busy || camera.isRecording || camera.isFinishingRecording || countdown > 0)
            }
        }
    }

    private var captureModePicker: some View {
        let available = !camera.isRecording && !camera.isFinishingRecording && !camera.isCapturing &&
            !camera.isSwitching && countdown == 0
        return SlidingCapsule(selectedRight: mode == .photo, canSelectLeft: available && camera.videoAvailable,
            canSelectRight: available, selectionChanged: { mode = $0 ? .photo : .video },
            height: 48) { proposedRight in
            HStack(spacing: 0) {
                ForEach(CaptureMode.allCases.reversed(), id: \.self) { value in
                    Button {
                        if mode == value { FotomarcoHaptics.play(.buttons) }
                        mode = value
                    } label: {
                        Text(value.rawValue).font(.subheadline.weight(.medium))
                            .foregroundStyle(proposedRight == (value == .photo) ? Color.white : Color.white.opacity(0.65))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!available || (value == .video && !camera.videoAvailable))
                    .accessibilityAddTraits(mode == value ? .isSelected : [])
                }
            }
        }.frame(maxWidth: 220)
    }

    private var cameraContent: some View {
        GeometryReader { geometry in
            let previewFrame = (PhotoAspect(rawValue: photoAspect) ?? .standard)
                .previewFrame(in: geometry.size, top: wordmarkBottom, bottom: shutterTop)
            ZStack {
                Color.black.ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { dismissZoomDial() }
                CameraPreview(session: camera.session, device: camera.activeDevice,
                              onCaptureRotation: camera.updateCaptureRotation, focus: camera.focus,
                              onTap: dismissZoomDial, onPinch: updatePreviewPinch)
                    .frame(width: previewFrame.width, height: previewFrame.height)
                    .clipped().contentShape(Rectangle())
                    .overlay {
                        StampOrientationContainer(deviceOrientation: stampDeviceOrientation) {
                        if stampEnabled && stampProfiles.selected.layout.template.hasFixedRenderer {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                GeometryReader { geometry in
                                    let snapshot = makeSnapshot(at: timeline.date)
                                    if let image = StampRenderer.overlay(size: geometry.size, snapshot: snapshot, map: nil, address: snapshot.cachedAddress) {
                                        if snapshot.layout.template == .largeMap && snapshot.mapEnabled && snapshot.location != nil {
                                            let mapBox = StampRenderer.workReportRect(in: geometry.size)
                                            StampMapPreview(snapshot: snapshot, markerSize: max(5, mapBox.height * 0.09), fillsFrame: true)
                                                .frame(width: mapBox.width, height: mapBox.height)
                                                .position(x: mapBox.midX, y: mapBox.midY)
                                        }
                                        Image(uiImage: image).resizable().frame(width: geometry.size.width, height: geometry.size.height).allowsHitTesting(false)
                                        let box = StampRenderer.workReportRect(in: geometry.size)
                                        Button { openStampEditor(.information) } label: { Color.clear.contentShape(Rectangle()) }
                                            .frame(width: box.width, height: box.height)
                                            .position(x: box.midX, y: box.midY)
                                            .accessibilityLabel("Personalizar carimbo")
                                        ForEach(Array(StampRenderer.fixedLogoHitRects(snapshot: snapshot, in: geometry.size).enumerated()), id: \.offset) { entry in
                                            let logoBox = entry.element
                                            Button { openStampEditor(.logo) } label: { Color.clear.contentShape(Rectangle()) }
                                                .frame(width: logoBox.width, height: logoBox.height)
                                                .position(x: logoBox.midX, y: logoBox.midY)
                                                .accessibilityLabel("Editar logotipo")
                                        }
                                        if snapshot.layout.template.usesMap && snapshot.layout.template != .largeMap && snapshot.mapEnabled && snapshot.location != nil {
                                            let mapBox = StampRenderer.fixedMapRect(in: geometry.size)
                                            StampMapPreview(snapshot: snapshot, markerSize: max(5, mapBox.width * 0.12))
                                                .frame(width: mapBox.width, height: mapBox.height)
                                                .position(x: mapBox.midX, y: mapBox.midY)
                                            Button { openStampEditor(.map) } label: { Color.clear.contentShape(Rectangle()) }
                                                .frame(width: mapBox.width, height: mapBox.height)
                                                .position(x: mapBox.midX, y: mapBox.midY)
                                                .accessibilityLabel("Editar mapa")
                                        }
                                        if snapshot.layout.template == .largeMap && snapshot.mapEnabled && snapshot.location != nil {
                                            let mapBox = StampRenderer.workReportRect(in: geometry.size)
                                            Button { openStampEditor(.map) } label: { Color.clear.contentShape(Rectangle()) }
                                                .frame(width: mapBox.width, height: mapBox.height * 0.64)
                                                .position(x: mapBox.midX, y: mapBox.minY + mapBox.height * 0.32)
                                                .accessibilityLabel("Editar mapa")
                                        }
                                    }
                                }
                            }
                        } else if stampEnabled && stampProfiles.selected.layout.mode == .separate {
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                SeparateLiveStamp(snapshot: makeSnapshot(at: timeline.date),
                                                  editMap: { openStampEditor(.map) },
                                                  editInformation: { openStampEditor(.information) },
                                                  editLogo: { openStampEditor(.logo) })
                            }
                        } else if stampEnabled && stampProfiles.selected.layout.template == .original {
                            VStack(spacing: 0) {
                                if stampProfiles.selected.layout.position == "top" { liveStamp }
                                Spacer(minLength: 0)
                                if stampProfiles.selected.layout.position != "top" && !showingZoomDial { liveStamp }
                            }
                        }
                        }
                    }
                    .overlay {
                        Rectangle().fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .opacity(modeTransitionBlur ? 1 : Double(gallerySwipeProgress) * 0.45)
                            .allowsHitTesting(false)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 18)
                            .onChanged { gesture in
                                guard cameraSurfaceVisible, !showingZoomDial, pinchZoom == nil,
                                      !camera.isRecording, !camera.isFinishingRecording, !camera.isCapturing,
                                      countdown == 0 else { return }
                                let movement = gesture.translation
                                guard movement.width > 0, movement.width > abs(movement.height) * 1.35 else { return }
                                if !reduceMotion { gallerySwipeProgress = min(1, movement.width / 180) }
                            }
                            .onEnded { gesture in
                                let shouldOpen = cameraSurfaceVisible && !showingZoomDial && pinchZoom == nil &&
                                    !camera.isRecording && !camera.isFinishingRecording && !camera.isCapturing &&
                                    countdown == 0 && CameraGallerySwipe.qualifies(gesture.translation)
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { gallerySwipeProgress = 0 }
                                if shouldOpen { FotomarcoHaptics.play(.gallery); openGallery() }
                            }
                    )
                    .position(x: previewFrame.midX, y: previewFrame.midY)
                    .animation(.easeInOut(duration: 0.2), value: photoAspect)
                if showGrid {
                    CameraGrid().frame(width: previewFrame.width, height: previewFrame.height)
                        .position(x: previewFrame.midX, y: previewFrame.midY)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    cameraHeader
                    if camera.processingPhotos > 0 && !camera.isRecording {
                        Text(camera.processingPhotos == 1 ? "Processando foto…" : "Processando \(camera.processingPhotos) fotos…")
                            .font(.caption).padding(8).background(.black.opacity(0.65), in: Capsule())
                    }
                    if camera.processingVideos > 0 && !camera.isRecording {
                        Text(camera.processingVideos == 1 ? "Aplicando carimbo ao vídeo…" : "Aplicando carimbo a \(camera.processingVideos) vídeos…")
                            .font(.caption).padding(8).background(.black.opacity(0.65), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if countdown > 0 {
                        Text("\(countdown)").font(.system(size: 56, weight: .bold, design: .rounded))
                            .shadow(radius: 6).accessibilityLabel("\(countdown) segundos")
                        Spacer(minLength: 8)
                    }
                    if recognitionDemand.qr || recognitionDemand.text {
                        LiveRecognitionBanner(engine: camera.recognition) { text in
                            selectedRecognizedText = RecognizedTextSelection(text: text)
                        }
                    }
                    VStack(spacing: 0) {
                    ZStack {
                    if showingZoomDial {
                        ZoomDialView(value: camera.zoomFactor, range: camera.zoomRange, presets: camera.zoomOptions, setZoom: camera.setZoom, editingChanged: zoomEditingChanged)
                            .frame(height: 132).transition(.move(edge: .bottom))
                    } else if !camera.zoomOptions.isEmpty {
                        CameraZoomStrip(presets: camera.zoomOptions, zoom: camera.zoomFactor, shutterCenterX: shutterCenterX) { factor in
                            if !suppressZoomPresetTap { camera.setZoom(factor) }
                        }.padding(.bottom, 16)
                    }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .updating($zoomTouchActive) { _, active, _ in active = true }
                            .onChanged { gesture in
                                let movement = gesture.translation
                                guard zoomDrag != nil || (abs(movement.width) >= 8 && abs(movement.width) > abs(movement.height)) else { return }
                                updateZoomDrag(movement.width)
                            }
                            .onEnded { _ in finishZoomDrag() }
                    )
                    .onChange(of: zoomTouchActive) { _, active in
                        if !active { finishZoomDrag() }
                    }
                    HStack {
                        Menu {
                            Picker("Perfil", selection: Binding(
                                get: { stampProfiles.selectedID },
                                set: { stampProfiles.select($0) }
                            )) {
                                Section("Espaço pessoal") {
                                    ForEach(stampProfiles.profiles) { item in
                                        Text(item.name.isEmpty ? "Sem nome" : item.name).tag(item.id)
                                    }
                                }
                                if !stampProfiles.organizationProfiles.isEmpty {
                                    Section("Organizações") {
                                        ForEach(stampProfiles.organizationProfiles) { item in
                                            Text(item.name.isEmpty ? "Sem nome" : item.name).tag(item.id)
                                        }
                                    }
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            ProfileLayoutIcon()
                                .frame(width: 29, height: 29)
                                .frame(width: 54, height: 54)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing || countdown > 0)
                        .accessibilityLabel("Escolher espaço e perfil")
                        .accessibilityValue(stampProfiles.selected.name.isEmpty ? "Sem nome" : stampProfiles.selected.name)
                        .opacity(camera.isRecording ? 0 : 1)
                        Spacer(minLength: 0)
                        Button {
                            guard !suppressQuickPhoto else { return }
                            if camera.isRecording && (mode == .video || quickRecordingLocked) {
                                stopVideoWithFeedback(); quickRecording = false; quickRecordingLocked = false
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
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named("MomentraCamera"))
                                } action: { frame in
                                    shutterTop = frame.minY - 1.5
                                    shutterCenterX = frame.midX
                                }
                                .contentShape(Circle())
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: camera.isRecording)
                        }
                        .disabled((mode == .video && !camera.ready) || camera.isCapturing || camera.isSwitching || (camera.isFinishingRecording && !quickRecording))
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
                            FotomarcoHaptics.play(.buttons)
                            mapLocation = makeSnapshot(at: Date()).location
                            mapAppearance = .satellite
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
                    }
                    .padding(.horizontal, max(28, geometry.size.width * 0.08))
                    .padding(.bottom, 16)
                    .offset(y: 6)
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
                        Button { FotomarcoHaptics.play(.buttons); openGallery() } label: {
                            ZStack {
                                if sessionCaptureCount > 3 {
                                    ForEach(0..<min(sessionCaptureCount - 3, 3), id: \.self) { index in
                                        RoundedRectangle(cornerRadius: 11)
                                            .fill(.black.opacity(0.55))
                                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.16), lineWidth: 1))
                                            .rotationEffect(.degrees(Double(index - 1) * 5))
                                            .offset(y: CGFloat(-index - 2))
                                    }
                                }
                                ForEach(Array(sessionCaptures.enumerated()).reversed(), id: \.offset) { index, capture in
                                    Image(uiImage: capture.image).resizable().scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                        .rotationEffect(.degrees(index == 0 ? 0 : (index == 1 ? -10 : 10)))
                                        .offset(x: index == 0 ? 0 : (index == 1 ? -4 : 4), y: index == 0 ? 0 : -3)
                                }
                                if sessionCaptures.isEmpty {
                                    Group {
                                        if let galleryThumbnail {
                                            Image(uiImage: galleryThumbnail.image).resizable().scaledToFill()
                                        } else {
                                            Image(systemName: "photo.on.rectangle").font(.title2)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(.white.opacity(0.16))
                                        }
                                    }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 11))
                                }
                            }.frame(width: 52, height: 52)
                                .overlay(alignment: .topTrailing) {
                                    if sessionCaptureCount > 0 {
                                        Text(sessionCaptureCount.formatted())
                                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                            .padding(.horizontal, 5).frame(minWidth: 19, minHeight: 19)
                                            .background(.yellow, in: Capsule())
                                            .offset(x: 7, y: -7).accessibilityHidden(true)
                                    }
                                }
                                .overlay { if cameraShareTask != nil { Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 11)); ProgressView().tint(.white) } }
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named("MomentraCamera"))
                                } action: { galleryThumbnailFrame = $0 }
                        }
                        .buttonStyle(CameraGalleryButtonStyle(share: shareCameraThumbnail))
                        .disabled(camera.isRecording || camera.isFinishingRecording || camera.isCapturing ||
                                  countdown > 0 || cameraShareTask != nil || cameraShare != nil)
                        .accessibilityLabel("Abrir capturas")
                        .accessibilityValue(sessionCaptureCount > 0 ? "\(sessionCaptureCount) capturas nesta sessão" : "")
                        .accessibilityActions {
                            if galleryThumbnail != nil {
                                Button("Compartilhar foto exibida", action: shareCameraThumbnail)
                            }
                        }
                        Spacer(minLength: 0)
                        captureModePicker
                        Spacer(minLength: 0)
                        Button { FotomarcoHaptics.play(.cameraFlip); camera.flipCamera() } label: {
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
                    let frame = CaptureMotion.aspectFit(flight.capture.image.size,
                                                        in: photoLanded ? galleryThumbnailFrame : previewFrame)
                    Image(uiImage: flight.capture.image).resizable()
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
        .overlay(alignment: .top) {
            if showSupportPanel {
                MomentraSupportPanel { setSupportPanel(false) }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .modifier(CameraHardwareCaptureModifier(enabled: scenePhase == .active && !showSettings && stampEditorSection == nil && selectedRecognizedText == nil && !showOriginals && !showMap && !showSettingsImport && !showSupportPanel && cameraShareTask == nil && cameraShare == nil, action: handleHardwareCapture))
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await updates.check() } }
        }
        .onChange(of: directUpdate.ready) { _, ready in
            if ready { Task { await updates.check() } }
        }
        .onAppear {
            stampMotion.start()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if UIDevice.current.orientation.isPortrait || UIDevice.current.orientation.isLandscape {
                stampDeviceOrientation = UIDevice.current.orientation
            }
            camera.setRecognition(qr: recognitionDemand.qr, text: recognitionDemand.text)
            camera.start()
            if !addressPreviewMigrated {
                var layout = stampProfiles.selected.layout
                layout.showsAddress = true
                stampProfiles.setLayout(layout)
                addressEnabled = true
                addressPreviewMigrated = true
            }
            refreshGalleryThumbnail()
            location.setEnabled(gpsEnabled)
            pressure.setEnabled(wantsPressure)
            refreshLogo()
            refreshAddress()
            publishCaptureContext()
        }
        .onDisappear { stampMotion.stop(); UIDevice.current.endGeneratingDeviceOrientationNotifications(); modeTransitionTask?.cancel(); modeTransitionBlur = false; finishPhotoFlight(); flashNoticeTask?.cancel(); dismissZoomDial(); cancelCountdown(); camera.setRecognition(qr: false, text: false); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel(); addressPreview.clear() }
        .onChange(of: stampMotion.orientation) { _, orientation in stampDeviceOrientation = orientation }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation.isPortrait || orientation.isLandscape { stampDeviceOrientation = orientation }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let orientation = UIDevice.current.orientation
                if orientation.isPortrait || orientation.isLandscape { stampDeviceOrientation = orientation }
                if didEnterBackground {
                    didEnterBackground = false
                    returnToCamera()
                }
                camera.start(); location.setEnabled(gpsEnabled); refreshAddress(); retryCloudCaptures()
            } else {
                if phase == .background { didEnterBackground = true }
                finishPhotoFlight(); dismissZoomDial(); CloudBackgroundScheduler.scheduleIfNeeded(); cancelCountdown(); camera.stop(); location.setEnabled(false); pressure.setEnabled(false); weather.cancel(); addressPreview.clear()
            }
        }
    }

    private var locationObservedCamera: some View {
        observedCamera
        .onReceive(location.$location) { fix in
            addressPreview.update(location: fix, enabled: canPreviewAddress)
            if canConsultForecast { weather.refresh(location: fix) }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            if canPreviewAddress { refreshAddress() }
            if canConsultForecast { weather.refresh(location: location.location) }
            if scenePhase == .active && Date().timeIntervalSince(lastCloudAttempt) >= 30 { retryCloudCaptures() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .momentraCloudCaptureStaged).receive(on: RunLoop.main)) { _ in
            retryCloudCaptures()
        }
        .onReceive(NotificationCenter.default.publisher(for: .momentraOpenCamera).receive(on: RunLoop.main)) { _ in
            returnToCamera()
            camera.start()
        }
    }

    private func returnToCamera() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showSettings = false
            stampEditorSection = nil
            showSupportPanel = false
            showOriginals = false
            cameraShareTask?.cancel()
            cameraShare = nil
            showMap = false
            showSettingsImport = false
            showAspectPanel = false
            selectedRecognizedText = nil
        }
    }

    private var trackedCamera: some View {
        locationObservedCamera
        .onChange(of: recognitionDemand) { _, demand in
            camera.setRecognition(qr: demand.qr, text: demand.text)
        }
        .onChange(of: wantsPressure) { _, enabled in pressure.setEnabled(enabled) }
        .onChange(of: gpsEnabled) { _, enabled in location.setEnabled(enabled); refreshAddress() }
        .onChange(of: stampProfiles.selected.layout.showsAddress) { _, _ in refreshAddress() }
        .onChange(of: stampEnabled) { _, _ in refreshAddress() }
        .onChange(of: mode) { _, _ in
            FotomarcoHaptics.play(.mode)
            refreshAddress()
            modeTransitionTask?.cancel()
            guard !reduceMotion else { modeTransitionBlur = false; return }
            withAnimation(.easeOut(duration: 0.25)) { modeTransitionBlur = true }
            modeTransitionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { modeTransitionBlur = false }
            }
        }
        .onChange(of: camera.zoomFactor) { old, new in
            let now = ProcessInfo.processInfo.systemUptime
            guard cameraSurfaceVisible, camera.ready, (old * 10).rounded() != (new * 10).rounded(),
                  now - lastZoomHaptic >= 0.1 else { return }
            lastZoomHaptic = now
            FotomarcoHaptics.play(.zoom)
        }
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
        .onReceive(camera.capturedPhoto) { _ in
            FotomarcoHaptics.play(.photo)
            showShutterFeedback()
        }
        .onReceive(camera.completedPhoto) { showCapturedPhoto($0) }
        .onChange(of: reduceMotion) { _, enabled in if enabled { finishPhotoFlight() } }
    }

    private var moreTrackedCamera: some View {
        trackedCamera
        .onChange(of: showMap) { _, _ in refreshAddress() }
        .onChange(of: stampProfiles.selectedID) { _, _ in refreshLogo(); refreshAddress(); publishCaptureContext() }
        .onChange(of: stampProfiles.selected.effectiveLogoName) { _, _ in refreshLogo() }
        .onChange(of: stampProfiles.selected.additionalLogoNames) { _, _ in refreshLogo() }
        .onChange(of: stampProfiles.selected.layout) { _, _ in publishCaptureContext() }
        .onChange(of: stampProfiles.selected.name) { _, _ in publishCaptureContext() }
        .onChange(of: stampProfiles.selected.note) { _, _ in publishCaptureContext() }
        .onChange(of: keepArchiveLocal) { _, _ in publishCaptureContext() }
        .onChange(of: keepArchiveOriginal) { _, _ in publishCaptureContext() }
        .onChange(of: canConsultForecast) { _, enabled in
            if enabled { weather.refresh(location: location.location) } else { weather.cancel() }
        }
        .onChange(of: archiveAccounts.accounts.map { $0.enabled ? $0.id : nil }) { _, _ in
            publishCaptureContext()
            retryCloudCaptures()
        }
        .onChange(of: showSettings) { _, showing in if !showing { publishCaptureContext() } }
        .onChange(of: stampEditorSection) { _, section in if section == nil { publishCaptureContext() } }

    }

    var body: some View {
        moreTrackedCamera
        .task(id: "\(businessIdentity.userID ?? "")-\(businessIdentity.emailVerified)") {
            stampProfiles.replaceOrganizationProfiles([])
            BusinessLegacyImportCoordinator.shared.configure(organizationID: nil, userID: nil)
            await BusinessProfileSync.refresh(into: stampProfiles, identity: businessIdentity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .businessOrganizationsDidChange)) { _ in
            Task { await BusinessProfileSync.refresh(into: stampProfiles, identity: businessIdentity) }
        }
        .sheet(item: $selectedRecognizedText) { item in RecognizedTextSheet(text: item.text) }
        .fullScreenCover(isPresented: $showOriginals) { OriginalsView(stampProfiles: stampProfiles) }
        .sheet(item: $cameraShare) { batch in
            batch.sheet {}
        }
        .alert("Carimbo da organização", isPresented: $showOrganizationReadOnly) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("O carimbo da organização é definido pelo administrador.")
        }
        .alert("Captura da equipe", isPresented: Binding(get: { businessCaptureNotice != nil }, set: { if !$0 { businessCaptureNotice = nil } })) {
            Button("OK", role: .cancel) { businessCaptureNotice = nil }
        } message: { Text(businessCaptureNotice ?? "") }
        .alert("Atualização do Photomark", isPresented: $showUpdateMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(directUpdate.message ?? "")
        }
        .alert("Não foi possível preparar a foto", isPresented: $cameraShareFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Confira se o arquivo ainda está disponível no iPhone ou na conta de armazenamento.")
        }
        .sheet(isPresented: $showMap) {
            NavigationStack {
                Group {
                    if let coordinate = mapLocation?.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))) {
                            Annotation("Localização", coordinate: coordinate, anchor: .center) {
                                MomentraLocationMarker(size: 28)
                            }
                        }
                        .mapStyle(mapAppearance == .satellite ? .imagery : .standard)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 6) {
                                ForEach(StampLayout.MapAppearance.allCases, id: \.self) { appearance in
                                    Button {
                                        FotomarcoHaptics.play(.buttons)
                                        mapAppearance = appearance
                                    } label: {
                                        Text(appearance == .map ? "Mapa" : "Satélite")
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 44)
                                            .background(
                                                appearance == mapAppearance ? Color.white.opacity(0.25) : .clear,
                                                in: Capsule()
                                            )
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(appearance == mapAppearance ? .isSelected : [])
                                }
                            }
                            .padding(12)
                        }
                    } else {
                        ContentUnavailableView("Localização indisponível", systemImage: "location.slash", description: Text("Ative o GPS nas configurações e aguarde uma localização recente."))
                    }
                }
                .navigationTitle("Mapa")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { FotomarcoHaptics.play(.buttons); showMap = false } } }
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(item: $stampEditorSection) { section in
            NavigationStack { StampLayoutEditor(store: stampProfiles, initialElement: section) }
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Photomark", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.clearError() } })) {
            Button("OK") { camera.clearError() }
        } message: { Text(camera.errorMessage ?? "") }
    }

    private func shareCameraThumbnail() {
        guard let thumbnail = galleryThumbnail, cameraSurfaceVisible, cameraShareTask == nil, cameraShare == nil,
              !camera.isRecording, !camera.isFinishingRecording, !camera.isCapturing, countdown == 0 else { return }
        FotomarcoHaptics.play(.quickShare)
        cameraShareTask = Task {
            defer { cameraShareTask = nil }
            do {
                let batch = try await GalleryShareBatch.prepare([thumbnail.file], copy: copyCameraThumbnail)
                try Task.checkCancellation()
                cameraShare = batch
            } catch {
                if !Task.isCancelled { cameraShareFailed = true }
            }
        }
    }

    private func copyCameraThumbnail(_ file: URL, to directory: URL) async throws -> URL {
        let root = file.deletingLastPathComponent().deletingLastPathComponent()
        let journal = CloudArchiveJournal(root: root)
        let localFile = root.appendingPathComponent("Processed", isDirectory: true)
            .appendingPathComponent(file.lastPathComponent)
        let copied = try await Task.detached(priority: .userInitiated) { () -> URL? in
            try journal.serializeCleanup {
                guard FileManager.default.fileExists(atPath: localFile.path) else { return nil }
                let copy = directory.appendingPathComponent(localFile.lastPathComponent)
                try FileManager.default.copyItem(at: localFile, to: copy)
                return copy
            }
        }.value
        if let copied { return copied }

        guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if let cached = CloudThumbnailCache.shareOriginal(root: root, captureID: id) {
            let destination = directory.appendingPathComponent(cached.lastPathComponent)
            do {
                try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: cached, to: destination) }.value
                return destination
            } catch { /* Cache can be evicted while a share starts; fall back to cloud. */ }
        }
        let receipt = try await Task.detached(priority: .userInitiated) { try journal.read(id) }.value
        var lastError: Error = CocoaError(.fileNoSuchFile)
        for delivery in receipt.plan.deliveries where delivery.phase == .verified {
            try Task.checkCancellation()
            guard let remoteID = delivery.stampedID,
                  let account = archiveAccounts.accounts.first(where: { $0.id == delivery.destination }) else { continue }
            let entry = CloudGalleryCatalog.Entry(id: remoteID, name: receipt.remoteName(stamped: true, destination: delivery.destination),
                                                  date: receipt.createdAt, revision: nil)
            guard let item = GalleryCloudItem.cachedPage([entry], for: account).items.first else { continue }
            do { return try await item.copy(to: directory) }
            catch { lastError = error }
        }
        throw lastError
    }

    private func requestUpdate(_ version: String, fromBanner: Bool = false) {
        guard !directUpdate.busy else { return }
        FotomarcoHaptics.play(.buttons)
        Task {
            await directUpdate.install(expectedVersion: version) {
                UpdateCloseReadiness.allowsClose(capturing: camera.isCapturing, switching: camera.isSwitching,
                    recording: camera.isRecording, finishing: camera.isFinishingRecording,
                    processingVideos: camera.processingVideos, processingPhotos: camera.processingPhotos,
                    cloudBusy: connectingArchive || cameraShareTask != nil || cameraShare != nil)
            }
            if fromBanner, directUpdate.message != nil { showUpdateMessage = true }
        }
    }

    private func openGallery() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { showOriginals = true }
    }

    private var archiveSettingsSection: some View {
        Section("Armazenamento e contas") {
            Button { FotomarcoHaptics.play(.buttons); connectArchive(.googleDrive) } label: {
                Label {
                    Text("Adicionar conta Google Drive")
                } icon: {
                    Image("GoogleDriveMark").renderingMode(.original).resizable().scaledToFit().frame(width: 24, height: 24)
                }
            }.disabled(connectingArchive)
            Button { FotomarcoHaptics.play(.buttons); connectArchive(.oneDrive) } label: {
                Label {
                    Text("Adicionar OneDrive ou Microsoft 365")
                } icon: {
                    Image("OneDriveMark").renderingMode(.original).resizable().scaledToFit().frame(width: 24, height: 24)
                }
            }.disabled(connectingArchive)
            if connectingArchive { ProgressView("Confirmando a conta…").font(.footnote) }
            if let archiveNotice { Text(archiveNotice).font(.footnote) }
            ForEach(archiveAccounts.accounts, id: \.id) { account in
                Toggle(isOn: Binding(get: { account.enabled }, set: { enabled in
                    applyArchivePolicy(keepLocal: keepArchiveLocal, destination: account.id, enabled: enabled)
                })) {
                    VStack(alignment: .leading) {
                        Text(account.id.provider == .googleDrive ? "Google Drive" : "OneDrive")
                        Text(account.label).font(.caption).foregroundStyle(.secondary)
                        Text(account.enabled ? "Conectada · envio ativo" : "Conectada · envio desativado")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.disabled(pendingArchivePolicy != nil)
            }
            Toggle("Armazenamento local", isOn: Binding(get: { effectiveLocalStorage }, set: {
                applyArchivePolicy(keepLocal: $0)
            }))
                .disabled(pendingArchivePolicy != nil || (keepArchiveLocal && archiveDestinations.isEmpty))
            Toggle("Manter também o original sem carimbo", isOn: $keepArchiveOriginal)
                .disabled(pendingArchivePolicy != nil)
            Text("A escolha vale para as próximas fotos e seus destinos. Com o envio pendente, a foto fica no iPhone para ser enviada quando houver conexão.")
                .font(.footnote).foregroundStyle(.secondary)
            if archiveStatus.pending + businessArchiveStatus.pending > 0 {
                Text("\(archiveStatus.pending + businessArchiveStatus.pending) captura(s) aguardando envio").font(.footnote)
            }
            if archiveStatus.needsAttention || businessArchiveStatus.needsAttention {
                Text("Há envios que precisam de atenção. Confira as contas, a conexão e o espaço disponível. Os arquivos pendentes ficam no iPhone.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            ForEach(archiveStatus.issues, id: \.self) { issue in
                Text(issue).font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var settingsSheet: some View {
            NavigationStack {
                Form {
                    Section("Conta e organização") {
                        NavigationLink("Conta Business") { BusinessAccountView() }
                            .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
                        NavigationLink("Gerenciar organização") { BusinessOrganizationsView(profiles: stampProfiles) }
                            .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
                    }
                    archiveSettingsSection
                    Section("Ajustes da câmera") {
                        NavigationLink("Estilos fotográficos") { PhotoStylesView(selected: $photoStyle) }
                            .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
                        Toggle("Escanear QR Codes", isOn: $scanQR)
                        Toggle("Mostrar Texto Detectado", isOn: $scanText)
                        Text("QR Codes e textos são reconhecidos automaticamente na prévia. Toque no resultado para abrir ou selecionar.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !camera.recognition.available {
                            Text("A leitura automática não está disponível com a configuração atual da câmera.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Preferências") {
                        NavigationLink("Vibrações") { HapticSettingsView { publishCaptureContext() } }
                            .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
                    }
                    Section("Composição") {
                        Toggle("Grade", isOn: $showGrid)
                    }
                    Section("Aparência") {
                        NavigationLink("Ícone do aplicativo") { AppIconPicker() }
                            .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
                    }
                    Section("Carimbo") {
                        NavigationLink("Layout e perfis") {
                            StampLayoutEditor(store: stampProfiles)
                        }
                        .simultaneousGesture(TapGesture().onEnded { FotomarcoHaptics.play(.buttons) })
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
                    Section {
                        LabeledContent("Versão instalada", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Indisponível")
                        if let version = updates.availableVersion {
                            Text("Nova versão disponível: \(version)").font(.headline)
                            if directUpdate.ready {
                                Button("Atualizar agora") { requestUpdate(version) }
                                    .disabled(directUpdate.busy)
                            } else {
                                Text("Para atualizar diretamente, ative uma vez pelo link pessoal de instalação.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Link("Ver instruções", destination: UpdateService.releasesURL)
                            }
                        }
                        Button(updates.checking ? "Verificando…" : "Buscar atualizações") {
                            FotomarcoHaptics.play(.buttons)
                            Task { await updates.check() }
                        }.disabled(updates.checking)
                        if let status = updates.status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        if let message = directUpdate.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        Link("Privacidade e créditos", destination: URL(string: "https://momentra-camera.vercel.app/privacidade.html")!)
                    } header: {
                        Text("Sobre")
                    } footer: {
                        Text("Desenvolvido por Marcos Rodrigues Pires · 2026")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .toggleStyle(DirectionalSwitchStyle())
                .navigationTitle("Configurações")
                .toolbar { Button("Concluído") { FotomarcoHaptics.play(.buttons); showSettings = false } }
                .alert("Conexão de armazenamento", isPresented: Binding(
                    get: { archiveConnectionError != nil },
                    set: { if !$0 { archiveConnectionError = nil } }
                )) {
                    Button("OK", role: .cancel) { archiveConnectionError = nil }
                } message: { Text(archiveConnectionError ?? "") }
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
                .alert("Photomark", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                    Button("OK") { importMessage = nil }
                } message: { Text(importMessage ?? "") }
            }
    }

    private func updatePreviewPinch(_ magnification: CGFloat?) {
        guard let magnification, camera.ready, !camera.isSwitching, !camera.isCapturing,
              !camera.isFinishingRecording, camera.zoomRange.lowerBound < camera.zoomRange.upperBound else {
            pinchZoom = nil
            return
        }
        if pinchZoom == nil { dismissZoomDial() }
        var zoom = pinchZoom ?? PreviewPinchZoom(value: camera.zoomFactor)
        let previous = zoom.value
        zoom.move(to: magnification, range: camera.zoomRange)
        pinchZoom = zoom
        if zoom.value != previous { camera.setZoom(zoom.value) }
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
            suppressZoomPresetTap = false
            withAnimation(.easeIn(duration: 0.22)) { showingZoomDial = false }
        }
    }

    private func updateZoomDrag(_ translation: CGFloat) {
        if zoomDrag == nil {
            guard camera.ready, !camera.isSwitching else { return }
            zoomDrag = ContinuousCameraZoom(value: camera.zoomFactor)
            suppressZoomPresetTap = true
            zoomEditingChanged(true)
            if !showingZoomDial {
                withAnimation(.easeOut(duration: 0.2)) { showingZoomDial = true }
            }
            zoomMotionTask = Task { @MainActor in
                let clock = ContinuousClock()
                var previous = clock.now
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                    let now = clock.now
                    let elapsed = previous.duration(to: now).components
                    previous = now
                    guard var drag = zoomDrag else { return }
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    let next = drag.advance(seconds: min(seconds, 0.1), range: camera.zoomRange)
                    if next != zoomDrag?.value { camera.setZoom(next) }
                    zoomDrag = drag
                }
            }
        }
        if var drag = zoomDrag {
            let previous = drag.value
            drag.move(to: translation, range: camera.zoomRange)
            if drag.value != previous { camera.setZoom(drag.value) }
            zoomDrag = drag
        }
    }

    private func finishZoomDrag() {
        guard zoomDrag != nil else { return }
        zoomMotionTask?.cancel()
        zoomMotionTask = nil
        zoomDrag = nil
        zoomEditingChanged(false)
        DispatchQueue.main.async {
            if zoomDrag == nil { suppressZoomPresetTap = false }
        }
    }

    private func dismissZoomDial() {
        finishZoomDrag()
        zoomDismissTask?.cancel()
        suppressZoomPresetTap = false
        if showingZoomDial {
            withAnimation(.easeIn(duration: 0.22)) { showingZoomDial = false }
        }
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
        guard camera.canStartPhoto() else { return }
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
        guard !stampProfiles.isOrganizationSelected else {
            quickRecording = false; quickReleasePending = false; quickRecordingLocked = false
            businessCaptureNotice = "O envio de vídeos da equipe ainda não está disponível. Escolha um perfil pessoal para gravar."
            return
        }
        let snapshot = stampEnabled ? makeSnapshot(at: Date()) : nil
        let profile = CaptureProfileTag(id: stampProfiles.selected.id, name: stampProfiles.selected.name)
        camera.startRecording(saveToPhotos: effectiveLocalStorage, snapshot: snapshot, profile: profile)
    }

    private func capturePhoto() {
        let isBusiness = stampProfiles.isOrganizationSelected
        let target: BusinessCaptureTarget?
        if isBusiness {
            guard let userID = businessIdentity.userID, businessIdentity.emailVerified else {
                businessCaptureNotice = "Entre novamente na sua conta para capturar pela organização."
                return
            }
            target = BusinessCaptureTarget(organizationID: stampProfiles.selectedID, userID: userID, keepsOriginal: keepArchiveOriginal)
        } else { target = nil }
        let snapshot = stampEnabled ? makeSnapshot(at: Date()) : nil
        camera.capture(snapshot: snapshot, aspect: PhotoAspect(rawValue: photoAspect) ?? .standard,
                       saveToPhotos: effectiveLocalStorage,
                       style: MomentraPhotoStyle(rawValue: photoStyle) ?? .natural,
                       profile: CaptureProfileTag(id: stampProfiles.selected.id, name: stampProfiles.selected.name),
                       archivePlan: isBusiness ? nil : currentArchivePlan, businessTarget: target)
    }

    private var archiveDestinations: [CloudDeliveryPlan.Destination] {
        archiveAccounts.accounts.filter(\.enabled).map(\.id)
    }

    private var effectiveLocalStorage: Bool { keepArchiveLocal || archiveDestinations.isEmpty }

    private var currentArchivePlan: CloudDeliveryPlan? {
        CloudDeliveryPlan(keepLocal: effectiveLocalStorage, destinations: archiveDestinations, keepOriginal: keepArchiveOriginal)
    }

    private func applyArchivePolicy(keepLocal: Bool, destination: CloudDeliveryPlan.Destination? = nil,
                                    enabled: Bool = false) {
        guard pendingArchivePolicy == nil else { return }
        var destinations = archiveDestinations
        if let destination {
            destinations.removeAll { $0 == destination }
            if enabled { destinations.append(destination) }
        }
        guard let proposed = CloudDeliveryPlan(keepLocal: keepLocal || destinations.isEmpty,
                                               destinations: destinations, keepOriginal: keepArchiveOriginal) else { return }
        pendingArchivePolicy = proposed
        archiveNotice = nil
        let sync = publishCaptureContext()
        Task { @MainActor in
            if let sync, !(await sync.value) {
                pendingArchivePolicy = nil
                archiveNotice = "Não foi possível atualizar os destinos da câmera bloqueada. Tente novamente."
                return
            }
            do {
                if let destination { try archiveAccounts.setEnabled(enabled, for: destination) }
                keepArchiveLocal = proposed.keepLocal
            } catch {
                archiveNotice = "Não foi possível alterar o destino."
            }
            pendingArchivePolicy = nil
            publishCaptureContext()
        }
    }

    private func connectArchive(_ provider: CloudDeliveryPlan.Provider) {
        guard let window = Self.presentingController()?.view.window else {
            archiveNotice = "Não foi possível abrir a autenticação."
            archiveConnectionError = archiveNotice
            return
        }
        connectingArchive = true
        archiveNotice = nil
        Task {
            defer { connectingArchive = false }
            do {
                try await archiveAccounts.connect(provider, presenting: window)
                archiveNotice = provider == .oneDrive ? "Conta OneDrive conectada." : "Conta Google Drive conectada."
            }
            catch {
                archiveNotice = error.localizedDescription
                if let failure = error as? CloudArchiveOAuth.Failure, case .cancelled = failure { return }
                archiveConnectionError = archiveNotice
            }
        }
    }

    private func retryCloudCaptures() {
        lastCloudAttempt = Date()
        guard scenePhase == .active else { return }
        Task {
            await BusinessLegacyImportCoordinator.shared.stageIfReady()
            async let personal = CloudArchiveDelivery.shared.drain()
            async let business = BusinessArchiveDelivery.shared.drain()
            let (personalStatus, businessStatus) = await (personal, business)
            if let personalStatus { archiveStatus = personalStatus }
            if let businessStatus { businessArchiveStatus = businessStatus }
        }
    }

    private func showShutterFeedback() {
        guard scenePhase == .active, mode == .photo, !showSettings, !showOriginals, !showAspectPanel, !showSupportPanel, !reduceMotion else { return }
        shutterFeedbackTask?.cancel()
        shutterOpacity = 0.35
        shutterFeedbackTask = Task {
            do { try await Task.sleep(for: .milliseconds(65)) } catch { return }
            withAnimation(.easeOut(duration: 0.10)) { shutterOpacity = 0 }
        }
    }

    private func setSupportPanel(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84)) {
            showSupportPanel = visible
        }
    }

    private func showCapturedPhoto(_ capture: CameraService.CapturePreview) {
        finishPhotoFlight()
        sessionCaptureCount += 1
        let thumbnail = capture.image.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? capture.image
        sessionCaptures.insert(.init(image: thumbnail, file: capture.file), at: 0)
        if sessionCaptures.count > 3 { sessionCaptures.removeLast() }
        galleryThumbnailRevision = UUID()
        guard scenePhase == .active, mode == .photo, !showSettings, !showOriginals, !showAspectPanel,
              !reduceMotion, !galleryThumbnailFrame.isEmpty else {
            galleryThumbnail = capture
            return
        }
        photoFlight = PhotoFlight(capture: capture)
    }

    private func finishPhotoFlight() {
        if let flight = photoFlight { galleryThumbnail = flight.capture }
        photoFlight = nil
        photoLanded = false
        shutterOpacity = 0
    }

    private func refreshGalleryThumbnail() {
        let revision = UUID()
        galleryThumbnailRevision = revision
        Task {
            let capture = await Task.detached(priority: .utility) { () -> CameraService.CapturePreview? in
                guard let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
                      let source = CloudThumbnailCache.latestCapturePreview(root: root) else { return nil }
                return .init(image: UIImage(cgImage: source.image), file: source.file)
            }.value
            if galleryThumbnailRevision == revision, photoFlight == nil { galleryThumbnail = capture }
        }
    }

    private func openStampEditor(_ section: StampLayoutEditor.Element) {
        FotomarcoHaptics.play(.buttons)
        guard !stampProfiles.isOrganizationSelected else { showOrganizationReadOnly = true; return }
        stampEditorSection = section
    }

    private var liveStamp: some View {
        HStack(spacing: 0) {
            if stampProfiles.selected.layout.horizontal == "right" { Spacer(minLength: 0) }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LiveStampView(snapshot: makeSnapshot(at: timeline.date),
                              editMap: { openStampEditor(.map) },
                              editInformation: { openStampEditor(.information) },
                                                  editLogo: { openStampEditor(.logo) })
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

    private var cameraSurfaceVisible: Bool {
        scenePhase == .active && !showSettings && stampEditorSection == nil && !showOriginals && !showMap && !showSupportPanel &&
            !showAspectPanel && !showSettingsImport && selectedRecognizedText == nil && cameraShare == nil
    }

    private struct RecognitionDemand: Equatable {
        let qr: Bool
        let text: Bool
    }

    private var recognitionDemand: RecognitionDemand {
        let scanning = cameraSurfaceVisible && !camera.isRecording && !camera.isFinishingRecording
        return RecognitionDemand(qr: scanning && scanQR, text: scanning && scanText)
    }

    private var wantsPressure: Bool {
        cameraSurfaceVisible && stampEnabled && stampProfiles.selected.layout.showsInformation
    }

    private var canConsultForecast: Bool {
        scenePhase == .active && gpsEnabled && stampEnabled && stampProfiles.selected.layout.showsInformation &&
            stampProfiles.selected.layout.showsForecast
    }

    private func makeSnapshot(at date: Date) -> StampSnapshot {
        let profile = stampProfiles.selected
        let names = [profile.effectiveLogoName] + profile.additionalLogoNames
        let mainLogo = names == loadedLogoNames ? logo : ProfileLogoStore.load(profile.effectiveLogoName)
        let additional = names == loadedLogoNames ? extraLogos : profile.additionalLogoNames.map { ProfileLogoStore.load($0) }
        return StampSnapshot(capturedAt: date, gpsEnabled: gpsEnabled,
            mapEnabled: profile.layout.showsMap, addressEnabled: profile.layout.showsAddress,
            cachedAddress: addressPreview.current(for: location.location, at: date), title: "", note: profile.note,
            logo: mainLogo, extraLogos: additional, logoCorner: "auto", compact: profile.layout.compact,
            position: profile.layout.position, horizontal: profile.layout.horizontal,
            longDate: profile.layout.dateFormat == "long", fontStyle: profile.layout.fontStyle,
            mapScale: profile.layout.mapScale, mapCorner: "auto",
            pressure: pressure.sample, forecast: canConsultForecast ? weather.current(location: location.location, at: date) : nil,
            location: location.location, heading: location.heading, layout: profile.layout)
    }

    @discardableResult
    private func publishCaptureContext() -> Task<Bool, Never>? {
        guard #available(iOS 18.0, *) else { return nil }
        let plan = pendingArchivePolicy ?? currentArchivePlan
        let context = MomentraCaptureContext(stampEnabled: stampEnabled, gpsEnabled: gpsEnabled,
            title: "", note: LockedCaptureMetadata.safeNote(stampProfiles.selected.note),
            compact: stampProfiles.selected.layout.compact, position: stampProfiles.selected.layout.position,
            horizontal: stampProfiles.selected.layout.horizontal, longDate: stampProfiles.selected.layout.dateFormat == "long",
            fontStyle: stampProfiles.selected.layout.fontStyle, aspect: photoAspect,
            saveToPhotos: plan?.keepLocal ?? effectiveLocalStorage,
            profileID: stampProfiles.selected.id, profileName: LockedCaptureMetadata.safeProfileName(stampProfiles.selected.name),
            cloudOwnerHash: nil,
            layoutData: (try? JSONEncoder().encode(stampProfiles.selected.layout.lockedCaptureLayout())).flatMap { $0.count <= 2000 ? $0 : nil },
            hasLogo: !stampProfiles.selected.effectiveLogoName.isEmpty || stampProfiles.selected.additionalLogoNames.contains(where: { !$0.isEmpty }),
            archivePlan: plan, hapticFocusIntensity: FotomarcoHaptics.intensity(.focus))
        let previous = captureContextTask
        let publish = Task { @MainActor in
            if let previous { _ = await previous.value }
            do {
                try await MomentraCaptureIntent.updateAppContext(context)
                return true
            } catch {
                return false
            }
        }
        captureContextTask = publish
        return publish
    }

    private func handleHardwareCapture() {
        guard camera.ready, !camera.isCapturing, !camera.isSwitching, !camera.isFinishingRecording else { return }
        if mode == .video {
            if camera.isRecording { stopVideoWithFeedback() } else { startVideoRecording() }
        } else if countdown > 0 {
            cancelCountdown()
        } else {
            schedulePhoto()
        }
    }

    private func stopVideoWithFeedback() {
        guard camera.isRecording, !camera.isFinishingRecording else { return }
        FotomarcoHaptics.play(.stopVideo)
        camera.stopRecording()
    }

    private var canPreviewAddress: Bool {
        scenePhase == .active && gpsEnabled && stampEnabled && stampProfiles.selected.layout.showsAddress
    }

    private func refreshAddress() { addressPreview.update(location: location.location, enabled: canPreviewAddress) }

    private func setLogo(_ name: String, for profileID: UUID) {
        stampProfiles.setLogo(name, for: profileID)
    }

    private func refreshLogo() {
        let profile = stampProfiles.selected
        logo = ProfileLogoStore.load(profile.effectiveLogoName)
        extraLogos = profile.additionalLogoNames.map { ProfileLogoStore.load($0) }
        loadedLogoNames = [profile.effectiveLogoName] + profile.additionalLogoNames
    }

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
    let editMap: () -> Void
    let editInformation: () -> Void
    let editLogo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if snapshot.mapEnabled, snapshot.location != nil {
                StampMapPreview(snapshot: snapshot, markerSize: 13)
                .frame(width: (snapshot.mapScale == "small" ? 60 : snapshot.mapScale == "large" ? 100 : 80) * snapshot.layout.mapSize * snapshot.layout.combinedSize,
                       height: (snapshot.mapScale == "small" ? 75 : snapshot.mapScale == "large" ? 125 : 100) * snapshot.layout.mapSize * snapshot.layout.combinedSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { Color.clear.contentShape(Rectangle()).onTapGesture(perform: editMap) }
                .accessibilityLabel("Editar mapa")
            }
            if snapshot.layout.showsInformation {
            VStack(alignment: snapshot.layout.textAlignment == "right" ? .trailing : snapshot.layout.textAlignment == "center" ? .center : .leading, spacing: 2) {
                ForEach(snapshot.informationLines(address: snapshot.addressEnabled && snapshot.location != nil ? snapshot.cachedAddress ?? "Buscando endereço…" : nil), id: \.self) { line in
                    Text(line).font(.system(size: (snapshot.compact ? 10 : 12) * snapshot.layout.informationSize * snapshot.layout.combinedSize, weight: .medium)).lineLimit(1).minimumScaleFactor(0.35)
                        .fontDesign(snapshot.fontStyle == "mono" ? .monospaced : snapshot.fontStyle == "serif" ? .serif : .default)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: editInformation)
            }
            Spacer(minLength: 0)
            if snapshot.layout.showsLogo, let logo = snapshot.logo {
                Image(uiImage: logo).resizable().scaledToFit().frame(width: 38 * snapshot.layout.logoSize * snapshot.layout.combinedSize,
                                                                 height: 38 * snapshot.layout.logoSize * snapshot.layout.combinedSize)
                    .accessibilityLabel("Editar logotipo")
                    .contentShape(Rectangle())
                    .onTapGesture(perform: editLogo)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}


private struct ProfileLayoutIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1.7)
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "person.crop.circle").resizable().scaledToFit()
                    RoundedRectangle(cornerRadius: 1.5).stroke(.white, lineWidth: 1.2)
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).stroke(.white, lineWidth: 1.2)
                    RoundedRectangle(cornerRadius: 1.5).stroke(.white, lineWidth: 1.2)
                }
            }.padding(4)
        }.foregroundStyle(.white)
    }
}
