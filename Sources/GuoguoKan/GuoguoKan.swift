import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = Library()
    func application(_ sender: NSApplication, open urls: [URL]) { library.open(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct GuoguoKanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("果果看", id: "viewer") {
            Viewer(library: delegate.library)
                .frame(minWidth: 240, minHeight: 200)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开图片或文件夹…") { delegate.library.openPanel() }.keyboardShortcut("o")
            }
            CommandMenu("图片文件") {
                Button("拷贝") { delegate.library.copyFile() }.keyboardShortcut("c")
                    .disabled(delegate.library.current == nil)
                Button("拷贝到文件夹…") { delegate.library.transferFile(move: false) }.keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(delegate.library.current == nil || delegate.library.busy)
                Button("移动到文件夹…") { delegate.library.transferFile(move: true) }.keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(delegate.library.current == nil || delegate.library.busy)
            }
            CommandMenu("看图") {
                Button("上一张") { delegate.library.move(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("下一张") { delegate.library.move(1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("上一个文件夹") { delegate.library.moveFolder(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("下一个文件夹") { delegate.library.moveFolder(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Divider()
                Button("单图 / 瀑布流") { delegate.library.gallery.toggle() }.keyboardShortcut("g")
                Button("适应窗口") { delegate.library.zoom("fit") }.keyboardShortcut("0")
                Button("实际像素") { delegate.library.zoom("actual") }.keyboardShortcut("1")
                Button("放大") { delegate.library.zoom("in") }.keyboardShortcut("+")
                Button("缩小") { delegate.library.zoom("out") }.keyboardShortcut("-")
                Button("向右旋转") { delegate.library.rotation = (delegate.library.rotation + 90) % 360 }.keyboardShortcut("r")
                Button("图片信息") { delegate.library.showInfo.toggle() }.keyboardShortcut("i")
            }
        }
    }
}

struct Viewer: View {
    @Bindable var library: Library
    @State private var targeted = false
    private var immersive: Bool { !library.gallery && library.current != nil }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if library.photos.isEmpty {
                    empty
                } else if library.gallery {
                    Waterfall(library: library)
                } else if let photo = library.current {
                    Canvas(photo: photo, rotation: library.rotation, command: library.zoomCommand, action: library.zoomAction, navigate: library.move, navigateFolder: library.moveFolder)
                }
                if library.busy {
                    ProgressView("正在处理…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .ignoresSafeArea(.container, edges: [])
            .overlay(alignment: .bottom) {
                if immersive {
                    HoverCaption(library: library)
                }
            }
            .contextMenu {
                ControlGroup {
                    Button("上一张", systemImage: "arrow.left") { library.move(-1) }
                    Button("下一张", systemImage: "arrow.right") { library.move(1) }
                    Button("上一个文件夹", systemImage: "folder.badge.arrow.backward") { library.moveFolder(-1) }
                    Button("下一个文件夹", systemImage: "folder.badge.arrow.forward") { library.moveFolder(1) }
                    Button("放大", systemImage: "plus.magnifyingglass") { library.zoom("in") }
                    Button("缩小", systemImage: "minus.magnifyingglass") { library.zoom("out") }
                    Button("收藏", systemImage: "star") { library.toggleFavorite() }
                    Button("导航栏", systemImage: "sidebar.left") { library.showNavigation.toggle() }
                }.controlGroupStyle(.palette)
                Divider()
                Button("显示检查器", systemImage: "info.circle") { library.showInfo.toggle() }.keyboardShortcut("i")
                Button("拷贝", systemImage: "doc.on.doc") { library.copyFile() }.keyboardShortcut("c")
                Button("拷贝到文件夹…", systemImage: "folder.badge.plus") { library.transferFile(move: false) }.keyboardShortcut("c", modifiers: [.command, .shift])
                Menu("移动", systemImage: "folder") {
                    Button(library.favorites.contains(library.current?.url.path ?? "") ? "取消收藏" : "收藏", systemImage: "star") { library.toggleFavorite() }
                    Divider()
                    Button("移动到文件夹…") { library.transferFile(move: true) }.keyboardShortcut("m", modifiers: [.command, .shift])
                    ForEach(library.destinations, id: \.self) { folder in
                        Button(folder.lastPathComponent) { library.transferFile(to: folder, move: true) }
                    }
                    Divider()
                    Button("添加文件夹…", systemImage: "plus") { library.addDestination() }
                }
                if let photo = library.current {
                    Button("在 Finder 中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                }
                Divider()
                Menu("旋转图片") {
                    Button("向右旋转") { library.rotation = (library.rotation + 90) % 360 }
                    Button("向左旋转") { library.rotation = (library.rotation + 270) % 360 }
                }
                Menu("显示模式") {
                    Button("单图") { library.gallery = false }
                    Button("瀑布流") { library.gallery = true }
                    Button("单列") { library.columns = 1; library.gallery = true }
                }
                Menu("调整窗口") {
                    Toggle("随图片自动调整", isOn: $library.autoSize)
                    Button("适合图片大小") { library.autoSize = true; library.zoom("fit") }
                    Button("进入 / 退出全屏") { NSApp.keyWindow?.toggleFullScreen(nil) }
                    Toggle("窗口置顶", isOn: $library.pinned)
                }
                Menu("图片尺寸") {
                    Button("适应窗口") { library.zoom("fit") }.keyboardShortcut("0")
                    Button("实际像素") { library.zoom("actual") }.keyboardShortcut("1")
                    Button("放大") { library.zoom("in") }
                    Button("缩小") { library.zoom("out") }
                }
                if let photo = library.current {
                    Menu("打开方式…") {
                        ForEach(NSWorkspace.shared.urlsForApplications(toOpen: photo.url), id: \.self) { app in
                            Button(app.deletingPathExtension().lastPathComponent) {
                                NSWorkspace.shared.open([photo.url], withApplicationAt: app, configuration: .init()) { _, error in
                                    if let error { Task { @MainActor in library.error = error.localizedDescription } }
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("移到废纸篓", systemImage: "trash") { library.trashCurrent() }
                Button("关闭", systemImage: "xmark") { NSApp.keyWindow?.performClose(nil) }
            }
            if library.showNavigation {
                ScrollView {
                    LazyVStack {
                        ForEach(library.filtered) { photo in
                            Thumbnail(photo: photo, width: 110).onTapGesture { library.choose(photo) }
                        }
                    }.padding(8)
                }.frame(width: 126)
            }
            if library.showInfo, let photo = library.current {
                Divider()
                inspector(photo).frame(width: 250)
            }
        }
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .overlay(alignment: .bottom) {
            if let status = library.fileStatus {
                Text(status).font(.callout).padding(12).background(.regularMaterial, in: Capsule()).padding(.bottom, 56)
                    .task(id: status) {
                        try? await Task.sleep(for: .seconds(3))
                        if !Task.isCancelled { library.fileStatus = nil }
                    }
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in library.open(urls); return !urls.isEmpty } isTargeted: { targeted = $0 }
        .safeAreaInset(edge: .top, spacing: 0) {
            if library.gallery && !library.photos.isEmpty {
                HStack {
                    TextField("搜索文件名", text: $library.query).textFieldStyle(.roundedBorder)
                    Stepper("\(library.columns) 列", value: $library.columns, in: 1...6).fixedSize()
                }.padding(8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                compactToolbar
                    .labelStyle(.iconOnly).buttonStyle(.plain).controlSize(.small)
                    .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(library.position).font(.caption).monospacedDigit()
            }
        }
        .toolbarVisibility(.visible, for: .windowToolbar)
        .background(ImageWindowConfiguration(library: library))
        .alert("图片操作", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("好") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }

    private var empty: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.tint)
            Text("果果看").font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("让每一张照片，好好被看见。").foregroundStyle(.secondary)
            Button("打开图片或文件夹…", action: library.openPanel).buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 12)
            Text("也可以将文件拖到这里  ·  ⌘O 打开").font(.callout).foregroundStyle(.tertiary)
        }.padding(40)
    }

    private var compactToolbar: some View {
        HStack(spacing: 10) {
            Button("打开", systemImage: "folder") { library.openPanel() }.help("打开（⌘O）")
            Button("上一张", systemImage: "arrow.left") { library.move(-1) }.help("上一张（↑）")
            Button("下一张", systemImage: "arrow.right") { library.move(1) }.help("下一张（↓）")
            Divider().frame(height: 14)
            Button("单图", systemImage: "square") { library.gallery = false }
            Button("瀑布流", systemImage: "square.grid.2x2") { library.columns = 3; library.gallery = true }
            Button("单列", systemImage: "rectangle.split.1x2") { library.columns = 1; library.gallery = true }
            Divider().frame(height: 14)
            Button("放大", systemImage: "plus.magnifyingglass") { library.zoom("in") }
            Button("缩小", systemImage: "minus.magnifyingglass") { library.zoom("out") }
            Button("旋转", systemImage: "rotate.right") { library.rotation = (library.rotation + 90) % 360 }
            Button("适合图片大小", systemImage: "viewfinder") { library.autoSize = true; library.zoom("fit") }
            Button("检查器", systemImage: "info.circle") { library.showInfo.toggle() }
            Button("导航栏", systemImage: "sidebar.left") { library.showNavigation.toggle() }
            Button("置顶", systemImage: library.pinned ? "pin.fill" : "pin") { library.pinned.toggle() }
        }.font(.system(size: 13)).fixedSize()
    }


    private func inspector(_ photo: Photo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("图片信息").font(.title3.bold())
                Text(photo.url.lastPathComponent).font(.headline).textSelection(.enabled)
                LabeledContent("尺寸", value: "\(photo.width) × \(photo.height)")
                LabeledContent("大小", value: ByteCountFormatter.string(fromByteCount: Int64(photo.bytes), countStyle: .file))
                LabeledContent("格式", value: photo.url.pathExtension.uppercased())
                Divider()
                Text(photo.detail.isEmpty ? "这张图片没有可显示的拍摄信息。" : photo.detail).font(.callout).textSelection(.enabled)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                ShareLink(item: photo.url) { Label("分享图片", systemImage: "square.and.arrow.up") }
                Text("旋转仅作用于预览，不修改原文件。").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
}

struct Waterfall: View {
    @Bindable var library: Library
    private var columns: [[Photo]] {
        var buckets = Array(repeating: [Photo](), count: library.columns)
        var heights = Array(repeating: CGFloat(0), count: library.columns)
        for photo in library.filtered {
            let index = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
            buckets[index].append(photo)
            heights[index] += 1 / photo.ratio + 0.14
        }
        return buckets
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if library.filtered.isEmpty {
                    ContentUnavailableView.search(text: library.query)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, photos in
                            LazyVStack(spacing: 14) {
                                ForEach(photos) { photo in
                                    Thumbnail(photo: photo, width: max(60, (geometry.size.width - 40 - CGFloat(library.columns - 1) * 14) / CGFloat(library.columns)))
                                        .onTapGesture(count: 2) { library.choose(photo) }
                                        .onTapGesture { library.selected = photo.url }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(library.selected == photo.url ? Color.accentColor : .clear, lineWidth: 2)
                                                .allowsHitTesting(false)
                                        }
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { library.choose(photo) }
                                        .contextMenu {
                                            Button("打开图片") { library.choose(photo) }
                                            Button("拷贝") { library.copyFile(photo) }.keyboardShortcut("c")
                                            Button("拷贝到文件夹…") { library.transferFile(photo, move: false) }.keyboardShortcut("c", modifiers: [.command, .shift])
                                            Button("移动到文件夹…") { library.transferFile(photo, move: true) }.keyboardShortcut("m", modifiers: [.command, .shift])
                                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                                        }
                                }
                            }
                        }
                    }.padding(20)
                }
            }
        }
    }
}

struct Thumbnail: View {
    let photo: Photo
    let width: CGFloat
    @State private var image: CGImage?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
                else { Image(systemName: failed ? "exclamationmark.triangle" : "photo").foregroundStyle(.secondary) }
            }.frame(width: max(1, width - 12), height: max(1, width - 12) / photo.ratio).clipShape(RoundedRectangle(cornerRadius: 10))
            Text("\(photo.url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(photo.bytes), countStyle: .file)))")
                .font(.caption).lineLimit(1).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }.padding(6).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: width).contentShape(Rectangle()).accessibilityLabel(photo.url.lastPathComponent)
        .task(id: Int(width)) {
            let loaded = await ImageLoader.shared.image(photo.url, pixels: min(1800, max(300, Int(width * 2))))
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
    }
}


struct HoverCaption: View {
    @Bindable var library: Library
    @State private var hovering = false
    var body: some View {
        HStack {
            Button { library.move(-1) } label: { Image(systemName: "chevron.left") }.help("上一张")
            Spacer()
            if let photo = library.current {
                Text("\(photo.url.lastPathComponent) · \(photo.width) × \(photo.height) · \(library.position)")
                    .font(.caption).lineLimit(1)
            }
            Spacer()
            Button { library.move(1) } label: { Image(systemName: "chevron.right") }.help("下一张")
        }.buttonStyle(.plain).padding(16).frame(height: 48)
        .background(.regularMaterial)
        .opacity(hovering ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
