import SwiftUI

struct DestinationShortcut: ViewModifier {
    let shortcut: RecordedShortcut?
    func body(content: Content) -> some View {
        if let shortcut, let key = shortcut.key.first {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: shortcut.swiftModifiers)
        } else {
            content
        }
    }
}

struct DestinationButton: View {
    @Bindable var library: Library
    let folder: URL
    let move: Bool
    var photo: Photo? = nil
    var body: some View {
        Button(folder.lastPathComponent) { library.transferFile(photo, to: folder, move: move) }
            .help(folder.path)
            .modifier(DestinationShortcut(shortcut: library.recordedShortcuts[RecordedShortcut.identifier(folder, move: move)]))
            .disabled((photo ?? library.current) == nil || library.busy)
    }
}
