import AppKit
import SwiftUI

struct WelcomeMaterial: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> NSVisualEffectView { NSVisualEffectView() }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .active : .inactive
    }
}
