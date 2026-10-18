import SwiftUI

struct DestinationShortcut: ViewModifier {
    let slot: Int?
    let move: Bool
    func body(content: Content) -> some View {
        if let slot, (1...9).contains(slot) {
            content.keyboardShortcut(KeyEquivalent(Character(String(slot))), modifiers: move ? [.command, .option, .shift] : [.command, .option])
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
            .modifier(DestinationShortcut(slot: library.destinationSlots[folder.path], move: move))
            .disabled((photo ?? library.current) == nil || library.busy)
    }
}
