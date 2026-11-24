import SwiftUI

struct BusinessPlansView: View {
    var onContinue: (() -> Void)? = nil
    @State private var business = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Image("IconPreviewOriginal").resizable().scaledToFit().frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
                    Text("Conheça os planos").font(.largeTitle.bold())
                    Picker("Plano", selection: $business) {
                        Text("Pro").tag(false)
                        Text("Business").tag(true)
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 15) {
                        feature("Câmera, carimbos e galeria")
                        feature("Salvamento em nuvem")
                        if business {
                            feature("Tudo do Pro para sua organização")
                            feature("Espaço de trabalho e carimbo compartilhado")
                            feature("Convites e acesso para até 500 pessoas")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.yellow)
                        Text(business ? "R$ 500,00 / ano" : "R$ 100,00 / ano").font(.headline)
                        Spacer()
                    }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    if business { Text("Por organização, para até 500 pessoas.").font(.footnote).foregroundStyle(.secondary) }
                    Text("A contratação dos planos está em preparação.").font(.footnote).foregroundStyle(.secondary)
                    if let onContinue {
                        OnboardingActionButton(title: "Continuar sem assinatura") { FotomarcoHaptics.play(.buttons); onContinue() }
                    }
                }.padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .navigationTitle("Planos").navigationBarTitleDisplayMode(.inline)
    }
    private func feature(_ title: String) -> some View {
        Label(title, systemImage: "checkmark").labelStyle(.titleAndIcon)
    }
}
