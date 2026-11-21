import SwiftUI
import UIKit

enum HapticEvent: String, CaseIterable, Identifiable {
    case buttons, switches, focus, zoom, photo, mode, stopVideo, quickShare, cameraFlip, gallery, editor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .buttons: return "Botões e navegação"
        case .switches: return "Interruptores"
        case .focus: return "Foco na câmera"
        case .zoom: return "Ajuste de zoom"
        case .photo: return "Captura de foto"
        case .mode: return "Troca entre foto e vídeo"
        case .stopVideo: return "Parar gravação"
        case .quickShare: return "Compartilhar pela miniatura"
        case .cameraFlip: return "Alternar câmera"
        case .gallery: return "Ações da galeria"
        case .editor: return "Edição e carimbos"
        }
    }
    var defaultIntensity: Double { self == .quickShare ? 0.4 : 0.2 }
    var storageKey: String { "native.haptics." + rawValue }
}

enum FotomarcoHaptics {
    static func intensity(_ event: HapticEvent, defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: event.storageKey) as? NSNumber else { return event.defaultIntensity }
        return min(1, max(0, value.doubleValue))
    }
    static func play(_ event: HapticEvent) { play(event, intensity: intensity(event)) }
    static func play(_ event: HapticEvent, intensity: Double) {
        let amount = min(1, max(0, intensity))
        guard amount > 0 else { return }
        UIImpactFeedbackGenerator(style: event == .quickShare ? .light : .soft)
            .impactOccurred(intensity: CGFloat(amount))
    }
}

struct HapticSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [HapticEvent: Double] = Dictionary(uniqueKeysWithValues: HapticEvent.allCases.map { ($0, FotomarcoHaptics.intensity($0)) })

    var body: some View {
        Form {
            Section {
                Text("Ajuste cada tipo de vibração. Em 0%, ela fica desligada. As mudanças são aplicadas ao salvar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(HapticEvent.allCases) { event in
                Section(event.title) {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.slash.fill").foregroundStyle(.secondary)
                            Slider(value: binding(for: event), in: 0...1, step: 0.05) { editing in
                                if !editing { FotomarcoHaptics.play(event, intensity: draft[event] ?? event.defaultIntensity) }
                            }
                            Image(systemName: "waveform").foregroundStyle(.secondary)
                        }
                        Text("\(Int(((draft[event] ?? event.defaultIntensity) * 100).rounded()))%")
                            .monospacedDigit().accessibilityLabel("Intensidade: \(Int(((draft[event] ?? event.defaultIntensity) * 100).rounded())) por cento")
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Vibrações")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    for event in HapticEvent.allCases { UserDefaults.standard.set(draft[event] ?? event.defaultIntensity, forKey: event.storageKey) }
                    FotomarcoHaptics.play(.buttons)
                    dismiss()
                }
            }
        }
    }
    private func binding(for event: HapticEvent) -> Binding<Double> {
        Binding(get: { draft[event] ?? event.defaultIntensity }, set: { draft[event] = $0 })
    }
}
