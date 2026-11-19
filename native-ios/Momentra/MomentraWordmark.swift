import SwiftUI
import UIKit

/// Vector-based wordmark, sized for the live camera header.
struct MomentraWordmark: View {
    private let fontName = "SnellRoundhand-Bold"
    private let fontSize: CGFloat = 25

    var body: some View {
        let letterHeight = UIFont(name: fontName, size: fontSize)?.xHeight ?? 10
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("M")
            Image(systemName: "location.circle.fill")
                .font(.system(size: letterHeight, weight: .semibold))
                .foregroundStyle(.yellow)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    (dimensions.height + letterHeight) / 2
                }
            Text("mentra")
        }
        .font(.custom(fontName, fixedSize: fontSize))
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentra")
    }
}
