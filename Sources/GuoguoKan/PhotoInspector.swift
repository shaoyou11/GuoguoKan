import AppKit
import SwiftUI

struct PhotoInspector: View {
    let photo: Photo
    let close: () -> Void
    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFit().frame(width: 32, height: 32)
                }
                Text(photo.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button("关闭详情", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.plain)
            }.padding(14)
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("路径").foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                        } label: {
                            Label(photo.url.deletingLastPathComponent().abbreviatedPath, systemImage: "folder.fill")
                                .lineLimit(2).truncationMode(.middle)
                        }.buttonStyle(.plain).help(photo.url.deletingLastPathComponent().path)
                        Spacer(minLength: 0)
                    }.padding(12).background(Color.primary.opacity(0.035))
                    row("文件大小", ByteCountFormatter.string(fromByteCount: Int64(photo.bytes), countStyle: .file), shaded: false)
                    row("创建日期", photo.created?.formatted(date: .numeric, time: .standard) ?? "未知", shaded: true)
                    row("像素", "\(photo.width) × \(photo.height)", shaded: false)
                    row("色彩", photo.color.isEmpty ? "未知" : photo.color, shaded: true)
                    if !photo.detail.isEmpty {
                        Text(photo.detail).frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled)
                    }
                    HStack {
                        ShareLink(item: photo.url) { Label("分享图片", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Text("旋转不修改原文件").font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                }
            }
        }
        .background(ControlMaterial(glass: true))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        .task(id: photo.url) {
            thumbnail = nil
            let image = await ImageLoader.shared.image(photo.url, pixels: 96)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }

    private func row(_ title: String, _ value: String, shaded: Bool) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(Color.primary.opacity(shaded ? 0.035 : 0))
    }
}

private extension URL {
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}
