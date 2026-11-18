import SwiftUI

/// Vector-based wordmark, sized for the live camera header.
struct MomentraWordmark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Text("Momentra").font(.custom("SnellRoundhand-Bold", size: 25))
            Image(systemName: "location.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.yellow)
                .offset(y: 3)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentra")
    }
}
