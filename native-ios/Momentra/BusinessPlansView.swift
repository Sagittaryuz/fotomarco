import SwiftUI

struct BusinessPlansView: View {
    var body: some View {
        List {
            Section("Pessoal") {
                Label("Câmera, carimbos e galeria", systemImage: "camera")
                Label("Suas contas de armazenamento", systemImage: "cloud")
            }
            Section("Business") {
                LabeledContent("Valor", value: "R$ 500 por organização / ano")
                LabeledContent("Equipe", value: "Até 500 pessoas")
                Label("Carimbo definido pela organização", systemImage: "person.2.badge.gearshape")
                Label("Fotos organizadas por membro", systemImage: "folder")
                Label("Convites e controle de acesso", systemImage: "person.badge.plus")
                Text("A contratação do plano está em preparação.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Planos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
