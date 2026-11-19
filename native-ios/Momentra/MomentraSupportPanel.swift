import SwiftUI
import UIKit

struct MomentraSupportPanel: View {
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var copied = false
    private let ink = Color(red: 0.07, green: 0.08, blue: 0.11)
    private let gold = Color(red: 1, green: 0.83, blue: 0.28)
    private let cyan = Color(red: 0.04, green: 0.63, blue: 0.93)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.14).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Image("EngineerSupportSticker").resizable().scaledToFill()
                    .frame(width: 162, height: 128, alignment: .top)
                    .clipped()
                    .offset(y: appeared || reduceMotion ? 0 : -130)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .accessibilityLabel("Marcos sorrindo com capacete de engenheiro")
                Text("Gosta tanto desse aplicativo?\nManda um Pix.")
                    .font(.system(.callout, design: .rounded).weight(.heavy))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(gold, in: RoundedRectangle(cornerRadius: 13))
                    .rotationEffect(.degrees(reduceMotion ? 0 : -2))
                    .padding(.horizontal, 15)
                Button {
                    UIPasteboard.general.string = "+5564992219172"
                    copied = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc").foregroundStyle(cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copied ? "Chave Pix copiada" : "Copiar chave Pix")
                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                            Text("649-9221-9172").font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                        if copied { Image(systemName: "checkmark.circle.fill").foregroundStyle(gold) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .frame(maxWidth: 265)
            .background(ink, in: RoundedRectangle(cornerRadius: 21))
            .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.12)) }
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .contentShape(Rectangle())
            .onTapGesture {}
            .padding(.horizontal, 16)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.43, dampingFraction: 0.72)) { appeared = true }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(.escape, dismiss)
        }
    }
}
