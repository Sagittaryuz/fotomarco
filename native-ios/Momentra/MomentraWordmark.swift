import SwiftUI

struct MomentraWordmark: View {
    private let symbolSize: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Fot")
            // The mark is clipped from the original icon, preserving its exact arrow and gradient.
            Image("IconPreviewOriginal")
                .resizable()
                .frame(width: symbolSize * 1024 / 356, height: symbolSize * 1024 / 356)
                .offset(x: symbolSize * 5 / 356, y: -symbolSize * 18 / 356)
                .frame(width: symbolSize, height: symbolSize)
                .clipShape(Circle())
                .environment(\.colorScheme, .dark)
            Text("marco")
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fotomarco")
    }
}
