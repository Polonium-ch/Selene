import SwiftUI
import AVFoundation
import AppKit

/// Hosts a `VideoDecodeRenderer`'s `AVSampleBufferDisplayLayer` in SwiftUI,
/// keeping the layer's frame in sync with the view's bounds on resize.
private final class VideoContainerView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }
}

struct VideoLayerView: NSViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> NSView {
        VideoContainerView(displayLayer: displayLayer)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
