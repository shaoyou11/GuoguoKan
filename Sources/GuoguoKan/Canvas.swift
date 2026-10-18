import AppKit
import SwiftUI

final class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return result }
        if documentView.frame.width < result.width { result.origin.x = (documentView.frame.width - result.width) / 2 }
        if documentView.frame.height < result.height { result.origin.y = (documentView.frame.height - result.height) / 2 }
        return result
    }
}

struct Canvas: NSViewRepresentable {
    let photo: Photo
    let rotation: Int
    let command: Int
    let action: String

    func makeNSView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.load(photo)
        return view
    }
    func updateNSView(_ view: PhotoScrollView, context: Context) {
        if view.rotation != rotation { view.rotation = rotation; view.render() }
        if view.lastCommand != command { view.lastCommand = command; view.apply(action) }
    }
}

@MainActor
final class PhotoScrollView: NSScrollView {
    private let picture = NSImageView()
    private let status = NSTextField(labelWithString: "正在加载…")
    private var decoded: CGImage?
    private var task: Task<Void, Never>?
    private var originalSize = NSSize(width: 1, height: 1)
    private var fitting = true
    var rotation = 0
    var lastCommand = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteredClipView()
        contentView.drawsBackground = false
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.01
        maxMagnification = 16
        picture.imageScaling = .scaleAxesIndependently
        picture.animates = false
        documentView = picture
        status.alignment = .center
        status.textColor = .secondaryLabelColor
        addSubview(status)
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleFit))
        doubleClick.numberOfClicksRequired = 2
        picture.addGestureRecognizer(doubleClick)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        picture.addGestureRecognizer(pan)
        pan.buttonMask = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(_ photo: Photo) {
        originalSize = NSSize(width: photo.width, height: photo.height)
        task?.cancel()
        task = Task { [weak self] in
            let image = await ImageLoader.shared.image(photo.url, pixels: min(8192, max(photo.width, photo.height)))
            guard !Task.isCancelled, let self else { return }
            decoded = image
            status.stringValue = image == nil ? "这张图片无法解码" : ""
            render()
        }
    }

    func render() {
        guard let decoded else { return }
        let swapped = rotation == 90 || rotation == 270
        let size = NSSize(width: swapped ? decoded.height : decoded.width, height: swapped ? decoded.width : decoded.height)
        let source = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        let angle = rotation
        let rendered = NSImage(size: size, flipped: false) { _ in
            let transform = AffineTransform(translationByX: size.width / 2, byY: size.height / 2)
            (transform as NSAffineTransform).concat()
            let turn = NSAffineTransform()
            turn.rotate(byDegrees: CGFloat(-angle))
            turn.concat()
            source.draw(in: NSRect(x: -source.size.width / 2, y: -source.size.height / 2, width: source.size.width, height: source.size.height))
            return true
        }
        picture.image = rendered
        picture.frame.size = size
        fit()
    }

    override func layout() {
        super.layout()
        status.frame = NSRect(x: 20, y: bounds.midY, width: max(0, bounds.width - 40), height: 24)
        if fitting { fit() }
    }

    private func fit() {
        guard picture.frame.width > 0, picture.frame.height > 0, contentSize.width > 0 else { return }
        let ratio = min(contentSize.width / picture.frame.width, contentSize.height / picture.frame.height)
        magnification = max(minMagnification, min(maxMagnification, ratio))
        fitting = true
        center()
    }

    private func center() {
        let size = contentView.bounds.size
        contentView.scroll(to: NSPoint(x: (picture.frame.width - size.width) / 2, y: (picture.frame.height - size.height) / 2))
        reflectScrolledClipView(contentView)
    }

    func apply(_ action: String) {
        if action == "fit" { fit(); return }
        fitting = false
        let scale = window?.backingScaleFactor ?? 2
        let fullPixels = rotation == 90 || rotation == 270 ? originalSize.height : originalSize.width
        let actual = fullPixels / max(picture.frame.width, 1) / scale
        let next = action == "actual" ? actual : magnification * (action == "in" ? 1.25 : 0.8)
        setMagnification(min(maxMagnification, max(minMagnification, next)), centeredAt: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
    }
    override func magnify(with event: NSEvent) { fitting = false; super.magnify(with: event) }
    @objc private func toggleFit() { fitting ? apply("actual") : fit() }
    @objc private func drag(_ recognizer: NSPanGestureRecognizer) {
        fitting = false
        let delta = recognizer.translation(in: contentView)
        let origin = contentView.bounds.origin
        contentView.scroll(to: NSPoint(x: origin.x - delta.x, y: origin.y - delta.y))
        reflectScrolledClipView(contentView)
        recognizer.setTranslation(.zero, in: contentView)
    }
}
