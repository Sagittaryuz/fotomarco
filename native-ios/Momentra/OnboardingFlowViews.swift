import SwiftUI
import UIKit
import AVFoundation
import Photos
import CoreLocation

struct OnboardingActionButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.glassProminent).tint(.yellow).foregroundStyle(.black)
        } else {
            Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
        }
    }
}

struct OnboardingIntroView: View {
    let continueAction: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            Image("IconPreviewOriginal").resizable().scaledToFit().frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous)).accessibilityHidden(true)
            MomentraWordmark().scaleEffect(1.35).padding(.vertical, 10)
            Text("Registre cada momento no lugar certo.").font(.title2.bold()).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 15) {
                Label("Fotos e vídeos com carimbos personalizados", systemImage: "camera.viewfinder")
                Label("Localização e data em cada registro", systemImage: "location.circle")
                Label("Um espaço pessoal e, quando quiser, sua equipe", systemImage: "person.2")
            }.font(.body).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 20)
            OnboardingActionButton(title: "Continuar") { FotomarcoHaptics.play(.buttons); continueAction() }
        }
        .padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}

@MainActor private final class OnboardingPermissions: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Kind: String, CaseIterable, Identifiable {
        case camera, microphone, photos, location
        var id: String { rawValue }
        var title: String { switch self { case .camera: "Câmera"; case .microphone: "Microfone"; case .photos: "Fotos"; case .location: "Localização" } }
        var detail: String { switch self {
        case .camera: "Fotografar e gravar vídeos."
        case .microphone: "Gravar o áudio dos vídeos."
        case .photos: "Salvar e visualizar suas capturas."
        case .location: "Adicionar a localização ao carimbo."
        } }
        var symbol: String { switch self { case .camera: "camera.fill"; case .microphone: "mic.fill"; case .photos: "photo.fill"; case .location: "location.fill" } }
    }
    enum Status: Equatable { case pending, allowed, limited, denied, restricted }
    @Published private(set) var states: [Kind: Status] = [:]
    private let location = CLLocationManager()
    override init() { super.init(); location.delegate = self; refresh() }

    func refresh() {
        func video(_ value: AVAuthorizationStatus) -> Status {
            switch value { case .authorized: .allowed; case .notDetermined: .pending; case .restricted: .restricted; default: .denied }
        }
        states[.camera] = video(AVCaptureDevice.authorizationStatus(for: .video))
        states[.microphone] = video(AVCaptureDevice.authorizationStatus(for: .audio))
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: states[.photos] = .allowed
        case .limited: states[.photos] = .limited
        case .notDetermined: states[.photos] = .pending
        case .restricted: states[.photos] = .restricted
        default: states[.photos] = .denied
        }
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: states[.location] = .allowed
        case .notDetermined: states[.location] = .pending
        case .restricted: states[.location] = .restricted
        default: states[.location] = .denied
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }
    func request(_ kind: Kind) {
        let status = states[kind] ?? .pending
        if status == .denied || status == .limited {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        guard status == .pending else { return }
        switch kind {
        case .location: location.requestWhenInUseAuthorization()
        case .camera, .microphone:
            let media: AVMediaType = kind == .camera ? .video : .audio
            Task { _ = await AVCaptureDevice.requestAccess(for: media); refresh() }
        case .photos: Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite); refresh() }
        }
    }
}

struct OnboardingPermissionsView: View {
    let continueAction: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissions = OnboardingPermissions()
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("IconPreviewOriginal").resizable().scaledToFit().frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)).accessibilityHidden(true)
                Text("Permissões").font(.largeTitle.bold())
                Text("Escolha o que o Photomark pode acessar. Você pode alterar essas permissões depois nos Ajustes do iPhone.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(OnboardingPermissions.Kind.allCases) { kind in
                        permissionRow(kind)
                        if kind != OnboardingPermissions.Kind.allCases.last { Divider().padding(.leading, 58) }
                    }
                }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                OnboardingActionButton(title: "Continuar") { FotomarcoHaptics.play(.buttons); continueAction() }
            }.padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in if phase == .active { permissions.refresh() } }
    }

    @ViewBuilder private func permissionRow(_ kind: OnboardingPermissions.Kind) -> some View {
        let state = permissions.states[kind] ?? .pending
        Button { FotomarcoHaptics.play(.buttons); permissions.request(kind) } label: {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol).font(.title3).foregroundStyle(.yellow).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title).foregroundStyle(.primary)
                    Text(kind.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if state == .allowed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Permitido") }
                else { Text(state == .pending ? "Ativar" : state == .limited ? "Limitado" : state == .restricted ? "Restrito" : "Ajustes")
                    .font(.caption).foregroundStyle(.yellow) }
            }.padding(15).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(state == .allowed || state == .restricted)
    }
}
