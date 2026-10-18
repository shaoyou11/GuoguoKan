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
                    Text("为目标目录分配 1–9：⌥⌘数字直接拷贝，⇧⌥⌘数字直接移动。快捷键固定绑定目录，不随最近使用排序改变。").font(.caption).foregroundStyle(.secondary)
                    ForEach(library.destinations, id: \.self) { folder in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(folder.lastPathComponent).lineLimit(1)
                                Spacer()
                                Picker("快捷键编号", selection: Binding(get: { library.destinationSlots[folder.path] ?? 0 }, set: { library.setDestinationSlot($0, for: folder) })) {
                                    Text("无").tag(0)
                                    ForEach(1...9, id: \.self) { slot in Text(String(slot)).tag(slot) }
                                }.labelsHidden().frame(width: 80)
                                Button("移除", role: .destructive) { library.removeDestination(folder) }
                            }
                            Text(folder.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
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
        let effect = (view.subviews.first as? NSVisualEffectView) ?? NSVisualEffectView()
        effect.material = glass ? .popover : .windowBackground
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.frame = view.bounds
        effect.autoresizingMask = [.width, .height]
        if effect.superview == nil { view.addSubview(effect) }
    }
}
