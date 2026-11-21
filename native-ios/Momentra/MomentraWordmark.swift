import SwiftUI
import UIKit

/// The mark divides two equal-width text runs on a shared baseline.
struct MomentraWordmark: View {
    private let size: CGFloat = 23

    var body: some View {
        let uiFont = UIFont.boldSystemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: uiFont]
        let leadingWidth = ["F", "o", "t"].reduce(CGFloat.zero) { $0 + ($1 as NSString).size(withAttributes: attributes).width }
        let trailingWidth = ("marco" as NSString).size(withAttributes: attributes).width
        let letterSpacing = max(0, (trailingWidth - leadingWidth) / 2)
        let markSize = uiFont.xHeight
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: letterSpacing) {
                Text("F")
                Text("o")
                Text("t")
            }
            ZStack {
                Circle().fill(Color.yellow)
                Image(systemName: "location.north.fill")
                    .font(.system(size: markSize * 0.55, weight: .bold))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(.black)
            }
            .frame(width: markSize, height: markSize)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                (dimensions.height + markSize) / 2
            }
            Text("marco")
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fotomarco")
    }
}
