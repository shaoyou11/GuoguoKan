import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

enum PhotoFileOperation {
    static func transfer(_ source: URL, to folder: URL, move: Bool) throws -> URL {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = folder.appendingPathComponent(source.lastPathComponent).resolvingSymlinksInPath().standardizedFileURL
        guard source != destination else {
            throw NSError(domain: "GuoguoKan", code: 1, userInfo: [NSLocalizedDescriptionKey: "图片已经在这个文件夹中。"])
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw NSError(domain: "GuoguoKan", code: 2, userInfo: [NSLocalizedDescriptionKey: "目标文件夹中已有同名文件，未覆盖任何文件。"])
        }
        if move { try FileManager.default.moveItem(at: source, to: destination) }
        else { try FileManager.default.copyItem(at: source, to: destination) }
        return destination
    }
}

struct Photo: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let width: Int
    let height: Int
    let bytes: Int
    let detail: String
    var ratio: CGFloat { CGFloat(max(width, 1)) / CGFloat(max(height, 1)) }
}

enum Catalog {
    static func adjacentFolder(to folder: URL, direction: Int) throws -> [Photo]? {
        let folder = folder.resolvingSymlinksInPath().standardizedFileURL
        let siblings = try FileManager.default.contentsOfDirectory(at: folder.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let index = siblings.firstIndex(of: folder), direction != 0 else { return nil }
        var next = index + (direction > 0 ? 1 : -1)
        while siblings.indices.contains(next) {
            let photos = try scan([siblings[next]])
            if !photos.isEmpty { return photos }
            next += direction > 0 ? 1 : -1
        }
        return nil
    }

    static func scan(_ urls: [URL]) throws -> [Photo] {
        let manager = FileManager.default
        var files = Set<URL>()
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let children = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                files.formUnion(children.map { $0.resolvingSymlinksInPath().standardizedFileURL })
            } else {
                files.insert(url.resolvingSymlinksInPath().standardizedFileURL)
            }
        }
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { url in
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 1
            let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 1
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            let swapped = (5...8).contains(orientation)
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            var lines: [String] = []
            if let model = tiff[kCGImagePropertyTIFFModel] as? String { lines.append("相机：\(model)") }
            if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String { lines.append("拍摄时间：\(date)") }
            if let aperture = exif[kCGImagePropertyExifFNumber] as? Double { lines.append("光圈：ƒ/\(aperture)") }
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double { lines.append("曝光：\(exposure) 秒") }
            return Photo(url: url, width: swapped ? rawHeight : rawWidth, height: swapped ? rawWidth : rawHeight,
                         bytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                         detail: lines.joined(separator: "\n"))
        }
    }
}

actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 160 * 1024 * 1024 }

    func image(_ url: URL, pixels: Int) -> CGImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(pixels)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

@MainActor @Observable
final class Library {
    var photos: [Photo] = []
    var selected: URL?
    var gallery = true
    var busy = false
    var error: String?
    var query = ""
    var columns = 3
    var showInfo = false
    var pinned = false
    var autoSize = true
    var showNavigation = false
    var destinations: [URL] = (UserDefaults.standard.stringArray(forKey: "destinations") ?? []).map { URL(fileURLWithPath: $0) }
    var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
    var fileStatus: String?
    var rotation = 0
    var zoomCommand = 0
    var zoomAction = "fit"
    private var request = UUID()
    var filtered: [Photo] { photos.filter { query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) } }
    var current: Photo? { photos.first { $0.url == selected } }
    var position: String {
        guard let index = filtered.firstIndex(where: { $0.url == selected }) else { return "\(filtered.count) 张照片" }
        return "\(index + 1) / \(filtered.count)"
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "打开"
        if panel.runModal() == .OK { open(panel.urls) }
    }

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let token = UUID()
        request = token
        busy = true
        error = nil
        query = ""
        let first = urls[0].resolvingSymlinksInPath().standardizedFileURL
        let isSingleImage = urls.count == 1 && UTType(filenameExtension: first.pathExtension)?.conforms(to: .image) == true
        let inputs = isSingleImage ? [first.deletingLastPathComponent()] : urls
        Task {
            do {
                let found = try await Task.detached(priority: .userInitiated) { try Catalog.scan(inputs) }.value
                guard request == token else { return }
                photos = found
                selected = found.contains(where: { $0.url == first }) ? first : found.first?.url
                gallery = !isSingleImage
                rotation = 0
                busy = false
                if found.isEmpty { error = "没有找到可读取的图片。请选择图片或直接包含图片的文件夹。" }
                NSDocumentController.shared.noteNewRecentDocumentURL(first)
            } catch {
                guard request == token else { return }
                busy = false
                self.error = "无法打开：\(error.localizedDescription)"
            }
        }
    }

    func choose(_ photo: Photo) { selected = photo.url; rotation = 0; gallery = false }
    func move(_ delta: Int) {
        let items = filtered
        guard !items.isEmpty else { return }
        let index = items.firstIndex(where: { $0.url == selected }) ?? 0
        selected = items[min(max(index + delta, 0), items.count - 1)].url
        rotation = 0
    }
    func zoom(_ action: String) { zoomAction = action; zoomCommand += 1 }

    func moveFolder(_ direction: Int) {
        guard !busy, let folder = current?.url.deletingLastPathComponent() else { return }
        busy = true
        let token = UUID()
        request = token
        Task {
            defer { if request == token { busy = false } }
            do {
                let found = try await Task.detached { try Catalog.adjacentFolder(to: folder, direction: direction) }.value
                guard request == token else { return }
                guard let found else { fileStatus = "没有更多包含图片的同级文件夹"; return }
                photos = found
                selected = found.first?.url
                query = ""
                rotation = 0
                fileStatus = found.first?.url.deletingLastPathComponent().lastPathComponent
            } catch { if request == token { self.error = error.localizedDescription } }
        }
    }

    func toggleFavorite() {
        guard let path = current?.url.path else { return }
        if favorites.contains(path) { favorites.remove(path) } else { favorites.insert(path) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    func addDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "添加文件夹"
        if panel.runModal() == .OK, let folder = panel.url { rememberDestination(folder) }
    }

    private func rememberDestination(_ folder: URL) {
        destinations.removeAll { $0 == folder }
        destinations.insert(folder, at: 0)
        destinations = Array(destinations.prefix(8))
        UserDefaults.standard.set(destinations.map(\.path), forKey: "destinations")
    }

    func trashCurrent() {
        guard !busy, let photo = current else { return }
        let alert = NSAlert()
        alert.messageText = "将这张图片移到废纸篓？"
        alert.informativeText = photo.url.lastPathComponent
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
            let index = photos.firstIndex(where: { $0.url == photo.url }) ?? 0
            photos.removeAll { $0.url == photo.url }
            selected = photos.isEmpty ? nil : photos[min(index, photos.count - 1)].url
            rotation = 0
        } catch { self.error = error.localizedDescription }
    }

    func copyFile(_ photo: Photo? = nil) {
        if photo == nil, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            editor.copy(nil)
            return
        }
        guard let photo = photo ?? current else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([photo.url as NSURL]) {
            fileStatus = "已拷贝，可在 Finder 中粘贴"
        }
    }

    func transferFile(_ photo: Photo? = nil, move: Bool) {
        guard !busy, let photo = photo ?? current else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = move ? "移动到这里" : "拷贝到这里"
        panel.message = "选择“\(photo.url.lastPathComponent)”的目标文件夹。同名文件不会被覆盖。"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        transferFile(photo, to: folder, move: move)
    }

    func transferFile(_ photo: Photo? = nil, to folder: URL, move: Bool) {
        guard !busy, let photo = photo ?? current else { return }
        rememberDestination(folder)
        busy = true
        let token = request
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try PhotoFileOperation.transfer(photo.url, to: folder, move: move)
                }.value
                guard request == token else { return }
                if move, let index = photos.firstIndex(where: { $0.url == photo.url }) {
                    photos.remove(at: index)
                    if selected == photo.url {
                        selected = photos.isEmpty ? nil : photos[min(index, photos.count - 1)].url
                        rotation = 0
                    }
                }
                busy = false
                fileStatus = move ? "图片已移动" : "图片已拷贝"
            } catch {
                guard request == token else { return }
                busy = false
                self.error = error.localizedDescription
            }
        }
    }
}
