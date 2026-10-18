import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = Library()
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            library.launching = false
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        library.launching = false
        return true
    }
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
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { delegate.library.showSettings = true }.keyboardShortcut(",")
            }
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
                Menu("拷贝到常用目录") {
                    ForEach(delegate.library.destinations, id: \.self) { folder in
                        DestinationButton(library: delegate.library, folder: folder, move: false)
                    }
                }
                Menu("移动到常用目录") {
                    ForEach(delegate.library.destinations, id: \.self) { folder in
                        DestinationButton(library: delegate.library, folder: folder, move: true)
                    }
                }
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
    @State private var toolbarHovered = false
    @State private var toolbarRevealed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var immersive: Bool { !library.gallery && library.current != nil }
    private var controlsVisible: Bool { !immersive || !library.autoHideToolbar || toolbarRevealed || library.showSettings }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if library.photos.isEmpty {
                    if !library.busy && !library.launching { empty }
                } else if library.gallery {
                    Waterfall(library: library)
                } else if let photo = library.current {
                    Canvas(photo: photo, rotation: library.rotation, command: library.zoomCommand, action: library.zoomAction, animatePhotos: library.animatePhotos && !reduceMotion, navigate: library.move, navigateFolder: library.moveFolder)
                }
                if library.busy && library.current == nil {
                    ProgressView("正在处理…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .ignoresSafeArea(.container, edges: [])
            .overlay(alignment: .bottom) {
                if immersive {
                    HoverCaption(library: library)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if immersive, let photo = library.current { CopyBadge(library: library, photo: photo).padding(8) }
            }
            .contextMenu {
                ControlGroup {
                    Button("上一张", systemImage: "arrow.left") { library.move(-1) }
                    Button("下一张", systemImage: "arrow.right") { library.move(1) }
                    Button { library.moveFolder(-1) } label: {
                        Label { Text("上一个文件夹") } icon: { FolderNavigationIcon(forward: false) }
                    }
                    Button { library.moveFolder(1) } label: {
                        Label { Text("下一个文件夹") } icon: { FolderNavigationIcon(forward: true) }
                    }
                    Button("放大", systemImage: "plus.magnifyingglass") { library.zoom("in") }
                    Button("缩小", systemImage: "minus.magnifyingglass") { library.zoom("out") }
                    Button("收藏", systemImage: "star") { library.toggleFavorite() }
                    Button("导航栏", systemImage: "sidebar.left") { library.showNavigation.toggle() }
                }.controlGroupStyle(.palette)
                Divider()
                Button("显示检查器", systemImage: "info.circle") { library.showInfo.toggle() }.keyboardShortcut("i")
                Button("拷贝", systemImage: "doc.on.doc") { library.copyFile() }.keyboardShortcut("c")
                CopyDestinationMenu(library: library, photo: library.current)
                Menu("移动", systemImage: "folder") {
                    Button(library.favorites.contains(library.current?.url.path ?? "") ? "取消收藏" : "收藏", systemImage: "star") { library.toggleFavorite() }
                    Divider()
                    Button("移动到文件夹…") { library.transferFile(move: true) }.keyboardShortcut("m", modifiers: [.command, .shift])
                    ForEach(library.destinations, id: \.self) { folder in
                        DestinationButton(library: library, folder: folder, move: true)
                    }
                    Divider()
                    Button("添加文件夹…", systemImage: "plus") { library.addDestination() }
                    Button("设置文件夹快捷键…") { library.showSettings = true }
                }
                if let photo = library.current {
                    Button("在 Finder 中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                }
                Divider()
                Menu("旋转图片") {
                    Button("向右旋转") { library.rotation = (library.rotation + 90) % 360 }
                    Button("向左旋转") { library.rotation = (library.rotation + 270) % 360 }
                    Button("旋转 180°") { library.rotation = (library.rotation + 180) % 360 }
                    Button("恢复方向") { library.rotation = 0 }
                }
                Menu("显示模式") {
                    Button("单图") { library.gallery = false }
                    Button("自适应网格") { library.galleryStyle = "grid"; library.gallery = true }
                    Button("瀑布流") { library.galleryStyle = "waterfall"; library.gallery = true }
                    Button("单列") { library.galleryStyle = "waterfall"; library.columns = 1; library.gallery = true }
                    Button("横排") { library.galleryStyle = "row"; library.gallery = true }
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
                Menu("自定义", systemImage: "terminal") {
                    ForEach(library.customScripts, id: \.self) { script in
                        Button(script.deletingPathExtension().lastPathComponent) { library.runCustomScript(script) }
                    }
                    Button("添加脚本…") { library.addCustomScript() }
                }
                Button("设置…", systemImage: "gearshape") { library.showSettings = true }.keyboardShortcut(",")
                Button("移到废纸篓", systemImage: "trash") { library.trashCurrent() }
                Button("关闭", systemImage: "xmark") { NSApp.keyWindow?.performClose(nil) }
            }
            if library.showNavigation {
                ScrollView {
                    LazyVStack {
                        ForEach(library.filtered) { photo in
                            Thumbnail(photo: photo, width: 110).onTapGesture { library.choose(photo) }
                                .overlay(alignment: .topTrailing) { CopyBadge(library: library, photo: photo) }
                        }
                    }.padding(8)
                }.frame(width: 126)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if library.showInfo, let photo = library.current {
                GeometryReader { geometry in
                    PhotoInspector(photo: photo) { library.showInfo = false }
                        .frame(width: min(380, max(200, geometry.size.width - 24)), height: min(360, max(140, geometry.size.height - 76)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(12)
                }.padding(.bottom, 38)
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
                    if library.galleryStyle == "waterfall" {
                        Stepper("\(library.columns) 列", value: $library.columns, in: 1...6).fixedSize()
                    }
                    Toggle("仅收藏", isOn: $library.onlyFavorites).toggleStyle(.button)
                }.padding(8).padding(.top, 38)
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                Text(library.current?.url.lastPathComponent ?? "果果看")
                    .font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 130)
                ScrollView(.horizontal, showsIndicators: false) {
                    compactToolbar.labelStyle(.iconOnly).buttonStyle(.plain).controlSize(.small)
                }
                Button("设置", systemImage: "gearshape") { library.showSettings = true }
                    .labelStyle(.iconOnly).buttonStyle(.plain).help("设置（⌘,）")
            }
            .padding(.leading, 78).padding(.trailing, 12).frame(height: 38)
            .background(ControlMaterial(glass: library.glassControls))
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controlsVisible)
        }
        .task(id: toolbarHovered) {
            guard !toolbarHovered else { return }
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { toolbarRevealed = false }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(ImageWindowConfiguration(library: library, controlsVisible: controlsVisible))
        .background(ToolbarTracking { hovering in
            toolbarHovered = hovering
            if hovering { toolbarRevealed = true }
        })
        .sheet(isPresented: $library.showSettings) { ViewerSettings(library: library) }
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
            Button("自适应网格", systemImage: "square.grid.2x2") { library.galleryStyle = "grid"; library.gallery = true }
            Button("瀑布流", systemImage: "rectangle.split.2x2") { library.galleryStyle = "waterfall"; library.columns = 3; library.gallery = true }
            Button("单列", systemImage: "rectangle.split.1x2") { library.galleryStyle = "waterfall"; library.columns = 1; library.gallery = true }
            Button("横排", systemImage: "rectangle.split.2x1") { library.galleryStyle = "row"; library.gallery = true }
            Divider().frame(height: 14)
            Button("放大", systemImage: "plus.magnifyingglass") { library.zoom("in") }.disabled(library.gallery || library.current == nil)
            Button("缩小", systemImage: "minus.magnifyingglass") { library.zoom("out") }.disabled(library.gallery || library.current == nil)
            Button("旋转", systemImage: "rotate.right") { library.rotation = (library.rotation + 90) % 360 }.disabled(library.gallery || library.current == nil)
            Button("适合图片大小", systemImage: "viewfinder") { library.autoSize = true; library.zoom("fit") }
            Button("检查器", systemImage: "info.circle") { library.showInfo.toggle() }
            Button("导航栏", systemImage: "sidebar.left") { library.showNavigation.toggle() }
            Button("置顶", systemImage: library.pinned ? "pin.fill" : "pin") { library.pinned.toggle() }
            Text(library.position).font(.caption).foregroundStyle(.secondary)
            if let photo = library.current { CopyBadge(library: library, photo: photo) }
        }.font(.system(size: 13)).fixedSize()
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
            if library.filtered.isEmpty {
                ContentUnavailableView("没有匹配的图片", systemImage: "photo", description: Text("可清空搜索或关闭“仅收藏”。"))
            } else if library.galleryStyle == "row" {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(library.filtered) { photo in tile(photo, width: 240, imageHeight: 180) }
                    }.padding(20)
                }
            } else if library.galleryStyle == "grid" {
                let count = max(1, Int(geometry.size.width / 180))
                let width = max(60, (geometry.size.width - 40 - CGFloat(count - 1) * 14) / CGFloat(count))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), spacing: 14) {
                        ForEach(library.filtered) { photo in tile(photo, width: width, imageHeight: width * 0.75) }
                    }.padding(20)
                }
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, photos in
                            LazyVStack(spacing: 14) {
                                ForEach(photos) { photo in
                                    tile(photo, width: max(60, (geometry.size.width - 40 - CGFloat(library.columns - 1) * 14) / CGFloat(library.columns)))
                                }
                            }
                        }
                    }.padding(20)
                }
            }
        }
    }
    private func tile(_ photo: Photo, width: CGFloat, imageHeight: CGFloat? = nil) -> some View {
        Thumbnail(photo: photo, width: width, imageHeight: imageHeight)
            .onTapGesture(count: 2) { library.choose(photo) }
            .onTapGesture { library.selected = photo.url }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(library.selected == photo.url ? Color.accentColor : .clear, lineWidth: 2).allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { CopyBadge(library: library, photo: photo) }
            .accessibilityAddTraits(.isButton).accessibilityAction { library.choose(photo) }
            .contextMenu {
                Button("打开图片") { library.choose(photo) }
                Button("拷贝") { library.copyFile(photo) }
                CopyDestinationMenu(library: library, photo: photo)
                Menu("移动") {
                    Button("选择文件夹…") { library.transferFile(photo, move: true) }
                    ForEach(library.destinations, id: \.self) { folder in
                        DestinationButton(library: library, folder: folder, move: true, photo: photo)
                    }
                    Button("添加常用文件夹…") { library.addDestination() }
                }
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
            }
    }
}

struct Thumbnail: View {
    let photo: Photo
    let width: CGFloat
    var imageHeight: CGFloat? = nil
    @State private var image: CGImage?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
                else { Image(systemName: failed ? "exclamationmark.triangle" : "photo").foregroundStyle(.secondary) }
            }.frame(width: max(1, width - 12), height: imageHeight ?? max(1, width - 12) / photo.ratio).clipShape(RoundedRectangle(cornerRadius: 10))
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
        }.buttonStyle(.plain).padding(12).frame(height: 38)
        .background(ControlMaterial(glass: library.glassControls))
        .opacity(hovering ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
