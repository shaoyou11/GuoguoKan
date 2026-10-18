import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

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
}
