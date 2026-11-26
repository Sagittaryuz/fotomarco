#if DEBUG
import CoreVideo
import Metal
import QuartzCore
import SwiftUI
import UIKit

/// Exercises the real Metal pipeline using synthetic pixels, without camera or user data.
struct CameraStylePreviewFixture: View {
    @State private var rendered = false
    var body: some View {
        VStack {
            SyntheticStyleView(rendered: $rendered)
                .frame(width: 200, height: 200)
                .accessibilityIdentifier("camera.style.synthetic.preview")
            Text(rendered ? "Quadro apresentado" : "Aguardando quadro")
                .accessibilityIdentifier("camera.style.synthetic.status")
        }
    }
}

private struct SyntheticStyleView: UIViewRepresentable {
    @Binding var rendered: Bool
    func makeUIView(context: Context) -> SyntheticStyleUIView {
        let view = SyntheticStyleUIView()
        view.onRendered = { rendered = true }
        return view
    }
    func updateUIView(_ view: SyntheticStyleUIView, context: Context) {}
}

private final class SyntheticStyleUIView: UIView {
    private let metalLayer = CAMetalLayer()
    private let renderer = CameraStylePreviewRenderer()
    private var timer: Timer?
    private var submitted = false
    var onRendered: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(metalLayer)
        renderer.attach(metalLayer)
        _ = renderer.configure(style: .mono, adjustments: .init(), enabled: true)
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(width: bounds.width * 2, height: bounds.height * 2)
        guard !submitted, bounds.width > 0, bounds.height > 0 else { return }
        submitted = true
        var optional: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                  attributes, &optional) == kCVReturnSuccess, let pixelBuffer = optional else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<64 {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<64 {
                    row[x * 4] = 20; row[x * 4 + 1] = 50; row[x * 4 + 2] = 230; row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.metalLayer.opacity == 1 {
                timer.invalidate(); self.onRendered?()
            } else {
                self.renderer.submit(pixelBuffer, rotation: 0, mirrored: false)
            }
        }
    }

    deinit { timer?.invalidate() }
}
#endif
