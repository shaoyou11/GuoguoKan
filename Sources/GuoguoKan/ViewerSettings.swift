import AppKit
import SwiftUI

struct FolderNavigationIcon: View {
    let forward: Bool
    var body: some View {
        Image(systemName: "folder")
            .overlay { Image(systemName: forward ? "arrow.right" : "arrow.left").font(.system(size: 8, weight: .semibold)).offset(y: 1) }
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
                Button(folder.lastPathComponent) { library.transferFile(photo, to: folder, move: false) }
            }
            Divider()
            Button("添加常用文件夹…", systemImage: "plus") { library.addDestination() }
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
                }
            }.formStyle(.grouped)
            Text("跟随系统的“减少动态效果”和“降低透明度”。").font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 430, height: 430)
    }
}

struct ControlMaterial: NSViewRepresentable {
    let glass: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let useGlass = glass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if (view.subviews.first is NSGlassEffectView) == useGlass, !view.subviews.isEmpty { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        let material: NSView
        if useGlass {
            let effect = NSGlassEffectView()
            effect.cornerRadius = 0
            effect.effectIsInteractive = true
            material = effect
        } else {
            let effect = NSVisualEffectView()
            effect.material = .windowBackground
            effect.blendingMode = .withinWindow
            effect.state = .active
            material = effect
        }
        material.frame = view.bounds
        material.autoresizingMask = [.width, .height]
        view.addSubview(material)
    }
}
