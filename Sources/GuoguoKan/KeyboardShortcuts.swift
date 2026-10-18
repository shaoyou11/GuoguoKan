import AppKit
import SwiftUI

struct RecordedShortcut: Codable, Equatable {
    let key: String
    let modifiers: UInt
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var label: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key.uppercased()
    }
    var swiftModifiers: EventModifiers {
        var result: EventModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
    static func identifier(_ folder: URL, move: Bool) -> String { folder.path + (move ? "|move" : "|copy") }
    static func read() -> [String: RecordedShortcut] {
        if let data = UserDefaults.standard.data(forKey: "recordedShortcuts"), let result = try? JSONDecoder().decode([String: RecordedShortcut].self, from: data) { return result }
        let slots = UserDefaults.standard.dictionary(forKey: "destinationSlots") as? [String: Int] ?? [:]
        var result: [String: RecordedShortcut] = [:]
        for (path, slot) in slots where (1...9).contains(slot) {
            for move in [false, true] {
                let flags: NSEvent.ModifierFlags = move ? [.command, .option, .shift] : [.command, .option]
                result[identifier(URL(fileURLWithPath: path), move: move)] = .init(key: String(slot), modifiers: flags.rawValue)
            }
        }
        return result
    }
    var validationError: String? {
        guard key.count == 1, key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value < 127 }) else { return "请使用字母、数字或标点键。" }
        guard flags.contains(.command) || flags.contains(.control) else { return "快捷键需要包含 Command 或 Control。" }
        if flags == .command && "acvxyzqwhmoinrgf0123456789,+-=".contains(key) { return "与应用或系统已有快捷键冲突，请换一组。" }
        if flags == [.command, .shift] && "cmozgs".contains(key) { return "与现有菜单快捷键冲突，请换一组。" }
        if flags.contains(.command) && key == "q" { return "此组合用于退出或锁定系统，不能分配。" }
        if flags == [.command, .option] && "hwm".contains(key) { return "与系统窗口快捷键冲突，请换一组。" }
        return nil
    }
    @MainActor
    func menuConflict(_ menu: NSMenu?) -> String? {
        for item in menu?.items ?? [] {
            if ["拷贝到常用目录", "移动到常用目录"].contains(item.title) { continue }
            if item.keyEquivalent.lowercased() == key && item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift]) == flags { return item.title }
            if let found = menuConflict(item.submenu) { return found }
        }
        return nil
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let value: RecordedShortcut?
    let record: (RecordedShortcut?) -> Bool
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.record = record
        view.savedTitle = value?.label ?? "录入快捷键"
        if view.monitor == nil { view.title = view.savedTitle }
    }
}

final class RecorderButton: NSButton {
    private static weak var active: RecorderButton?
    var record: ((RecordedShortcut?) -> Bool)?
    var savedTitle = "录入快捷键"
    var monitor: Any?
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        toolTip = "点击后按组合键；Esc 取消；退格清除。"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginRecording() {
        Self.active?.stopRecording()
        stopRecording()
        Self.active = self
        title = "按下组合键…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.keyCode == 53 { stopRecording(); return nil }
            let flags = event.modifierFlags.intersection([.command, .control, .shift, .option])
            if [51, 117].contains(event.keyCode), flags.isEmpty {
                if record?(nil) == true { stopRecording() }
                return nil
            }
            let shortcut = RecordedShortcut(key: (event.charactersIgnoringModifiers ?? "").lowercased(), modifiers: flags.rawValue)
            if record?(shortcut) == true { stopRecording() }
            else { title = "冲突，请重录…" }
            return nil
        }
    }
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if Self.active === self { Self.active = nil }
        title = savedTitle
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}
