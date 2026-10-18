import SwiftUI

struct ViewerButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration, enabled: enabled, reduceMotion: reduceMotion)
    }
    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        let reduceMotion: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .frame(minWidth: 24, minHeight: 26)
                .foregroundStyle(.primary.opacity(enabled ? 0.78 : 0.28))
                .background(.primary.opacity(enabled && (hovered || configuration.isPressed) ? (configuration.isPressed ? 0.14 : 0.07) : 0), in: RoundedRectangle(cornerRadius: 7))
                .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.92 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}
