import AppKit
import SwiftUI

enum ImageWindowGeometry {
    static func contentSize(image: CGSize, available: CGSize, scale: CGFloat, sidebar: CGFloat) -> CGSize {
        let width = max(1, image.width / max(scale, 1))
        let height = max(1, image.height / max(scale, 1))
        let ratio = min(1, max(1, available.width - sidebar) / width, max(1, available.height) / height)
        return CGSize(width: max(240, width * ratio + sidebar), height: max(200, height * ratio))
    }
}
struct ImageWindowConfiguration: NSViewRepresentable {
    @Bindable var library: Library
    let controlsVisible: Bool
    final class Coordinator {
        var key = ""
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let photo = library.current
        let gallery = library.gallery
        let pinned = library.pinned
        let autoSize = library.autoSize
        let rotation = library.rotation
        let sidebar: CGFloat = library.showNavigation ? 126 : 0
        let readyForWelcome = photo == nil && !library.busy && !library.launching
        let key = "\(photo?.url.path ?? "")|\(gallery)|\(rotation)|\(sidebar)|\(autoSize)|\(library.windowFitRequest)|\(readyForWelcome)"
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = readyForWelcome
            window.level = pinned ? .floating : .normal
            window.title = photo?.url.lastPathComponent ?? "果果看"
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = !controlsVisible
            }
            guard key != coordinator.key else { return }
            coordinator.key = key
            if readyForWelcome, let screen = window.screen, !window.styleMask.contains(.fullScreen) {
                window.setContentSize(NSSize(width: min(880, screen.visibleFrame.width - 24), height: min(580, screen.visibleFrame.height - 24)))
                window.center()
                return
            }
            guard autoSize, !gallery, let photo, !window.styleMask.contains(.fullScreen),
                  let screen = window.screen else { return }
            let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let chrome: CGFloat = 0
            let swapped = rotation == 90 || rotation == 270
            let image = CGSize(width: swapped ? photo.height : photo.width, height: swapped ? photo.width : photo.height)
            let size = ImageWindowGeometry.contentSize(image: image,
                available: CGSize(width: visible.width, height: visible.height - chrome),
                scale: window.backingScaleFactor, sidebar: sidebar)
            let frameSize = CGSize(width: min(size.width, visible.width), height: min(size.height + chrome, visible.height))
            let origin = CGPoint(x: min(max(window.frame.midX - frameSize.width / 2, visible.minX), visible.maxX - frameSize.width),
                                 y: min(max(window.frame.midY - frameSize.height / 2, visible.minY), visible.maxY - frameSize.height))
            window.setFrame(CGRect(origin: origin, size: frameSize), display: true)
        }
    }
}
