import AppKit
import SwiftUI

struct FolderNavigationIcon: View {
    let forward: Bool
    var body: some View {
        Image(nsImage: symbol)
    }
    private var symbol: NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?.draw(in: NSRect(x: 0, y: 0, width: 20, height: 18))
            NSImage(systemSymbolName: forward ? "arrow.right" : "arrow.left", accessibilityDescription: nil)?.draw(in: NSRect(x: 6, y: 3, width: 8, height: 8))
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct CopyDestinationMenu: View {
    @Bindable var library: Library
    let photo: Photo?
    var body: some View {
        Menu("拷贝到", systemImage: "folder.badge.plus") {
            Button("选择文件夹…") { library.transferFile(photo, move: false) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            ForEach(library.destinations, id: \.self) { folder in
                DestinationButton(library: library, folder: folder, move: false, photo: photo)
            }
            Divider()
            Button("添加常用文件夹…", systemImage: "plus") { library.addDestination() }
            Button("设置文件夹快捷键…") { library.showSettings = true }
        }.disabled(photo == nil || library.busy)
    }
}

struct CopyBadge: View {
    @Bindable var library: Library
    let photo: Photo
    var body: some View {
        if let destination = library.copiedPhotos[photo.url.path] {
            Label("已拷贝", systemImage: "checkmark.circle.fill")
                .font(.caption2).padding(5).background(.regularMaterial, in: Capsule())
                .help("已成功拷贝到：\(destination)").padding(4)
        } else if library.clipboardPhoto == photo.url {
            Label("已放入剪贴板", systemImage: "doc.on.clipboard")
                .font(.caption2).padding(5).background(.regularMaterial, in: Capsule()).padding(4)
        }
    }
}

struct ViewerSettings: View {
    @Bindable var library: Library
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置").font(.title2)
                Spacer()
                Button("完成") { library.showSettings = false }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section("看图") {
                    Toggle("自动隐藏顶部工具栏", isOn: $library.autoHideToolbar)
                    Text("鼠标移到顶边显示，离开后自动收起，不改变图片位置。").font(.caption).foregroundStyle(.secondary)
                    Toggle("切换图片时淡入", isOn: $library.animatePhotos)
                    Toggle("使用玻璃控制栏", isOn: $library.glassControls)
                    Toggle("窗口随图片大小调整", isOn: $library.autoSize)
                }
                Section("文件操作") {
                    Text("↑↓ 切图 · ←→ 切文件夹\n⌘C 放入剪贴板 · ⇧⌘C 拷贝到文件夹 · ⇧⌘M 移动")
                        .font(.callout)
                    Text("“已拷贝”表示已成功写入目标文件夹；放入剪贴板会单独标注。历史标记不保证目标文件一直存在。").font(.caption).foregroundStyle(.secondary)
                    Button("添加常用目标文件夹…") { library.addDestination() }
                    Text("点击录入后按下组合键；Esc 取消，退格清除。拷贝与移动可分别设置，旧编号快捷键自动保留。").font(.caption).foregroundStyle(.secondary)
                    if let error = library.shortcutError { Text(error).foregroundStyle(.red).font(.callout).accessibilityLabel("快捷键冲突：\(error)") }
                    ForEach(library.destinations, id: \.self) { folder in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(folder.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button("移除", role: .destructive) { library.removeDestination(folder) }
                            }
                            HStack {
                                Text("拷贝")
                                ShortcutRecorder(value: library.recordedShortcuts[RecordedShortcut.identifier(folder, move: false)]) {
                                    library.recordShortcut($0, folder: folder, move: false)
                                }.frame(width: 150, height: 28)
                                Text("移动")
                                ShortcutRecorder(value: library.recordedShortcuts[RecordedShortcut.identifier(folder, move: true)]) {
                                    library.recordShortcut($0, folder: folder, move: true)
                                }.frame(width: 150, height: 28)
                            }
                            Text(folder.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Text("检测应用内重复及常见系统冲突；其他软件的全局快捷键占用无法完全检测。").font(.caption).foregroundStyle(.secondary)
                }
                Section("更新") {
                    Button("检查更新…") { UpdateManager.shared.check() }
                    Toggle("自动检查更新", isOn: Binding(get: { UpdateManager.shared.controller.updater.automaticallyChecksForUpdates }, set: { UpdateManager.shared.controller.updater.automaticallyChecksForUpdates = $0 }))
                    Text("从发布版本获取签名更新，下载后确认安装。请将应用放在本机“应用程序”目录，不要直接从 iCloud 或压缩包运行。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Text("跟随系统的“减少动态效果”和“降低透明度”。").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 480, height: 540)
    }
}

struct ControlMaterial: NSViewRepresentable {
    let glass: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let useGlass = glass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if (view.subviews.first is NSGlassEffectView) != useGlass { view.subviews.first?.removeFromSuperview() }
        let effect: NSView
        if useGlass {
            let glassView = (view.subviews.first as? NSGlassEffectView) ?? NSGlassEffectView()
            glassView.style = .clear
            glassView.cornerRadius = 14
            glassView.tintColor = NSColor.white.withAlphaComponent(0.12)
            glassView.effectIsInteractive = true
            effect = glassView
        } else {
            let solid = (view.subviews.first as? NSVisualEffectView) ?? NSVisualEffectView()
            solid.material = .windowBackground
            solid.blendingMode = .withinWindow
            solid.state = .active
            effect = solid
        }
        effect.frame = view.bounds
        effect.autoresizingMask = [.width, .height]
        if effect.superview == nil { view.addSubview(effect) }
    }
}
