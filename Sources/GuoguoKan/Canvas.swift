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
    let animatePhotos: Bool
    let resizeWindowOnZoom: Bool
    let scrollNavigation: Bool
    var reportZoom: (String) -> Void
    var navigate: (Int) -> Void
    var navigateFolder: (Int) -> Void

    func makeNSView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.animatePhotos = animatePhotos
        view.rotation = rotation
        view.resizeWindowOnZoom = resizeWindowOnZoom
        view.scrollNavigation = scrollNavigation
        view.lastCommand = command
        view.reportZoom = reportZoom
        view.navigate = navigate
        view.navigateFolder = navigateFolder
        view.load(photo)
        return view
    }
    func updateNSView(_ view: PhotoScrollView, context: Context) {
        view.reportZoom = reportZoom
        view.navigate = navigate
        view.navigateFolder = navigateFolder
        view.animatePhotos = animatePhotos
        view.resizeWindowOnZoom = resizeWindowOnZoom
        view.scrollNavigation = scrollNavigation
        if view.loadedURL != photo.url {
            view.rotation = rotation
            view.load(photo)
        } else if view.rotation != rotation { view.rotation = rotation; view.render() }
        if view.lastCommand != command { view.lastCommand = command; view.apply(action) }
    }
}

@MainActor
final class PhotoScrollView: NSScrollView {
    private let picture = NSImageView()
    private let status = NSTextField(labelWithString: "正在加载…")
    private var decoded: CGImage?
    private var task: Task<Void, Never>?
    private var loadingIndicatorTask: Task<Void, Never>?
    private var originalSize = NSSize(width: 1, height: 1)
    private var fitting = true
    private var lastScrollTime: TimeInterval = 0
    private var wheelDelta: CGFloat = 0
    private var gestureNavigated = false
    private(set) var loadedURL: URL?
    private(set) var displayedImageURL: URL?
    private var heldMagnification: CGFloat?
    private var heldFitting = false
    var navigate: ((Int) -> Void)?
    var navigateFolder: ((Int) -> Void)?
    var rotation = 0
    var lastCommand = 0
    var animatePhotos = true
    var resizeWindowOnZoom = false
    var scrollNavigation = true
    var reportZoom: ((String) -> Void)?

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
        status.stringValue = ""
        status.textColor = .secondaryLabelColor
        addSubview(status)
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleFit))
        doubleClick.numberOfClicksRequired = 2
        picture.addGestureRecognizer(doubleClick)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        picture.addGestureRecognizer(pan)
        pan.buttonMask = 1
        let press = NSPressGestureRecognizer(target: self, action: #selector(pressZoom(_:)))
        press.minimumPressDuration = 0.35
        picture.addGestureRecognizer(press)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(_ photo: Photo) {
        loadedURL = photo.url
        picture.layer?.removeAllAnimations()
        picture.image = nil
        decoded = nil
        displayedImageURL = nil
        heldMagnification = nil
        loadingIndicatorTask?.cancel()
        status.stringValue = ""
        originalSize = NSSize(width: photo.width, height: photo.height)
        task?.cancel()
        let pixels = min(8192, max(photo.width, photo.height))
        if let cached = ImageLoader.shared.cached(photo.url, pixels: pixels) {
            decoded = cached
            displayedImageURL = photo.url
            render()
            return
        }
        loadingIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, displayedImageURL == nil, loadedURL == photo.url else { return }
            status.stringValue = "正在读取图片…"
        }
        task = Task { [weak self] in
            let image = await ImageLoader.shared.image(photo.url, pixels: pixels)
            guard !Task.isCancelled, let self, loadedURL == photo.url else { return }
            loadingIndicatorTask?.cancel()
            let transition = animatePhotos && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            decoded = image
            displayedImageURL = image == nil ? nil : photo.url
            status.stringValue = image == nil ? "这张图片无法解码" : ""
            if image == nil { picture.image = nil }
            render()
            if transition, image != nil {
                picture.wantsLayer = true
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.12
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                picture.layer?.add(fade, forKey: "photoTransition")
            }
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
        let target = max(minMagnification, min(maxMagnification, ratio))
        if abs(magnification - target) > 0.0001 { magnification = target }
        fitting = true
        hasVerticalScroller = false
        hasHorizontalScroller = false
        center()
    }

    private func center() {
        let size = contentView.bounds.size
        contentView.scroll(to: NSPoint(x: (picture.frame.width - size.width) / 2, y: (picture.frame.height - size.height) / 2))
        reflectScrolledClipView(contentView)
    }

    func apply(_ action: String) {
        if action == "fit" { fit(); showZoom(); return }
        if ["in", "out"].contains(action), fitting, resizeWindowOnZoom,
           let window, !window.styleMask.contains(.fullScreen), let screen = window.screen {
            let factor: CGFloat = action == "in" ? 1.2 : 1 / 1.2
            let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let size = NSSize(width: window.frame.width * factor, height: window.frame.height * factor)
            if size.width <= available.width, size.height <= available.height, size.width >= 240, size.height >= 200 {
                let origin = NSPoint(x: min(max(window.frame.midX - size.width / 2, available.minX), available.maxX - size.width), y: min(max(window.frame.midY - size.height / 2, available.minY), available.maxY - size.height))
                window.setFrame(NSRect(origin: origin, size: size), display: true)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    window.contentView?.layoutSubtreeIfNeeded()
                    fit()
                    showZoom()
                }
                return
            }
        }
        fitting = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        let scale = window?.backingScaleFactor ?? 2
        let fullPixels = rotation == 90 || rotation == 270 ? originalSize.height : originalSize.width
        let actual = fullPixels / max(picture.frame.width, 1) / scale
        let next = action == "actual" ? actual : magnification * (action == "in" ? 1.2 : 1 / 1.2)
        setMagnification(min(maxMagnification, max(minMagnification, next)), centeredAt: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
        showZoom()
    }
    private func showZoom() {
        let pixels = rotation == 90 || rotation == 270 ? originalSize.height : originalSize.width
        let percentage = magnification * picture.frame.width * (window?.backingScaleFactor ?? 2) / max(pixels, 1) * 100
        reportZoom?("\(Int(percentage.rounded()))%\(fitting ? " · 适应窗口" : "")")
    }
    override func magnify(with event: NSEvent) { fitting = false; super.magnify(with: event); showZoom() }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
            if abs(event.scrollingDeltaY) > 0 { apply(event.scrollingDeltaY > 0 ? "in" : "out") }
            return
        }
        guard fitting else { super.scrollWheel(with: event); return }
        guard scrollNavigation else { wheelDelta = 0; gestureNavigated = false; return }
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) { gestureNavigated = false; wheelDelta = 0 }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { gestureNavigated = false; return }
        if !event.phase.isEmpty && gestureNavigated { return }
        if event.timestamp - lastScrollTime > 0.3 { wheelDelta = 0 }
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        wheelDelta += horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 35 : 1
        if abs(wheelDelta) >= threshold && event.timestamp - lastScrollTime > 0.22 {
            lastScrollTime = event.timestamp
            let direction = wheelDelta < 0 ? 1 : -1
            wheelDelta = 0
            gestureNavigated = true
            if horizontal { navigateFolder?(direction) } else { navigate?(direction) }
        }
    }
    @objc private func pressZoom(_ recognizer: NSPressGestureRecognizer) {
        if recognizer.state == .began {
            heldMagnification = magnification
            heldFitting = fitting
            fitting = false
            setMagnification(min(maxMagnification, magnification * 2), centeredAt: recognizer.location(in: picture))
            showZoom()
        } else if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            if let saved = heldMagnification { magnification = saved }
            heldMagnification = nil
            fitting = heldFitting
            if fitting { fit() }
            showZoom()
        }
    }
    @objc private func toggleFit() {
        if fitting { apply("actual") }
        else { fit(); showZoom() }
    }
    @objc private func drag(_ recognizer: NSPanGestureRecognizer) {
        guard !fitting else { return }
        let delta = recognizer.translation(in: contentView)
        let origin = contentView.bounds.origin
        contentView.scroll(to: NSPoint(x: origin.x - delta.x, y: origin.y - delta.y))
        reflectScrolledClipView(contentView)
        recognizer.setTranslation(.zero, in: contentView)
    }
}
