import SwiftUI

struct MomentraWordmark: View {
    var body: some View {
        Image("FotomarcoWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 32)
            .accessibilityLabel("Fotomarco")
    }
}
