import AppKit
import SwiftUI

struct ToolbarTracking: NSViewRepresentable {
    var hoverChanged: (Bool) -> Void
    func makeNSView(context: Context) -> ToolbarTrackingView { ToolbarTrackingView() }
    func updateNSView(_ view: ToolbarTrackingView, context: Context) { view.hoverChanged = hoverChanged }
}

final class ToolbarTrackingView: NSView {
    var hoverChanged: ((Bool) -> Void)?
    private var monitor: Any?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .mouseExited]) { [weak self] event in
            guard let self, event.window === self.window, let window = self.window else { return event }
            let top = window.contentView?.bounds.height ?? window.frame.height
            self.hoverChanged?(event.type != .mouseExited && event.locationInWindow.y >= top - 44)
            return event
        }
    }
}
