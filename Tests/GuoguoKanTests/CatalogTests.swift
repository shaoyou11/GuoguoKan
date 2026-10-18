import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import GuoguoKan

final class CatalogTests: XCTestCase {
    @MainActor func testNavigationHonorsFilterAndResetsRotation() async throws {
        let folder = try fixtureFolder()
        try makeImage(folder.appendingPathComponent("first.tiff"))
        try makeImage(folder.appendingPathComponent("second.tiff"))
        let library = Library()
        library.photos = try Catalog.scan([folder])
        library.selected = library.photos[0].url
        library.query = "second"
        library.rotation = 90
        library.move(1)
        XCTAssertEqual(library.current?.url.lastPathComponent, "second.tiff")
        XCTAssertEqual(library.rotation, 0)
        library.move(1)
        XCTAssertEqual(library.current?.url.lastPathComponent, "second.tiff")
    }

    @MainActor func testFavoriteFilterDoesNotChangeSourceCatalog() async throws {
        let folder = try fixtureFolder()
        try makeImage(folder.appendingPathComponent("first.tiff"))
        try makeImage(folder.appendingPathComponent("second.tiff"))
        let library = Library()
        library.photos = try Catalog.scan([folder])
        let chosen = library.photos[1].url
        library.favorites = [chosen.path]
        library.onlyFavorites = true
        XCTAssertEqual(library.filtered.map(\.url), [chosen])
        XCTAssertEqual(library.photos.count, 2)
        library.onlyFavorites = false
        XCTAssertEqual(library.filtered.count, 2)
    }

    func testPortraitWindowFitsScreenWithoutWideLetterboxing() {
        let size = ImageWindowGeometry.contentSize(image: CGSize(width: 1320, height: 2868), available: CGSize(width: 1400, height: 850), scale: 2, sidebar: 0)
        XCTAssertEqual(size.height, 850, accuracy: 0.01)
        XCTAssertEqual(size.width / size.height, 1320.0 / 2868.0, accuracy: 0.001)
    }

    func testLandscapeWindowIncludesInspectorAndDoesNotUpscale() {
        let size = ImageWindowGeometry.contentSize(image: CGSize(width: 1200, height: 800), available: CGSize(width: 1400, height: 850), scale: 2, sidebar: 251)
        XCTAssertEqual(size.width, 851)
        XCTAssertEqual(size.height, 400)
    }

    func testFolderNavigationSkipsEmptyAndUsesNaturalOrder() throws {
        let parent = try fixtureFolder()
        let first = parent.appendingPathComponent("相册1")
        let empty = parent.appendingPathComponent("相册2")
        let last = parent.appendingPathComponent("相册10")
        for folder in [first, empty, last] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try makeImage(first.appendingPathComponent("first.tiff"))
        try makeImage(last.appendingPathComponent("last.tiff"))
        XCTAssertEqual(try Catalog.adjacentFolder(to: first, direction: 1)?.first?.url.lastPathComponent, "last.tiff")
        XCTAssertEqual(try Catalog.adjacentFolder(to: last, direction: -1)?.first?.url.lastPathComponent, "first.tiff")
        XCTAssertNil(try Catalog.adjacentFolder(to: first, direction: -1))
        XCTAssertNil(try Catalog.adjacentFolder(to: last, direction: 1))
    }

    func testCopyPreservesSourceAndContents() throws {
        let sourceFolder = try fixtureFolder()
        let destination = try fixtureFolder()
        let source = sourceFolder.appendingPathComponent("photo.tiff")
        try makeImage(source)
        let original = try Data(contentsOf: source)
        let copied = try PhotoFileOperation.transfer(source, to: destination, move: false)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: copied), original)
    }

    func testMovePreservesBytesAndRemovesOnlySource() throws {
        let sourceFolder = try fixtureFolder()
        let destination = try fixtureFolder()
        let source = sourceFolder.appendingPathComponent("photo.tiff")
        let untouched = sourceFolder.appendingPathComponent("keep.tiff")
        try makeImage(source)
        try makeImage(untouched)
        let original = try Data(contentsOf: source)
        let moved = try PhotoFileOperation.transfer(source, to: destination, move: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: moved), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: untouched.path))
    }

    func testTransferRejectsCollisionAndSameFolder() throws {
        let sourceFolder = try fixtureFolder()
        let destination = try fixtureFolder()
        let source = sourceFolder.appendingPathComponent("photo.tiff")
        let existing = destination.appendingPathComponent("photo.tiff")
        try makeImage(source)
        let sentinel = Data("existing".utf8)
        try sentinel.write(to: existing)
        for move in [false, true] {
            XCTAssertThrowsError(try PhotoFileOperation.transfer(source, to: destination, move: move))
            XCTAssertThrowsError(try PhotoFileOperation.transfer(source, to: sourceFolder, move: move))
        }
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func fixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GuoguoKanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @MainActor
    func testRecordedShortcutsRejectConflictsAndPersist() async {
        let saved = UserDefaults.standard.object(forKey: "recordedShortcuts")
        defer { UserDefaults.standard.set(saved, forKey: "recordedShortcuts") }
        let library = Library()
        library.recordedShortcuts = [:]
        let folder = URL(fileURLWithPath: "/tmp/recording-test")
        let reserved = RecordedShortcut(key: "c", modifiers: NSEvent.ModifierFlags.command.rawValue)
        XCTAssertFalse(library.recordShortcut(reserved, folder: folder, move: false))
        let valid = RecordedShortcut(key: "k", modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
        XCTAssertTrue(library.recordShortcut(valid, folder: folder, move: false))
        XCTAssertFalse(library.recordShortcut(valid, folder: folder, move: true))
        XCTAssertNotNil(library.shortcutError)
        XCTAssertEqual(RecordedShortcut.read()[RecordedShortcut.identifier(folder, move: false)], valid)
        XCTAssertTrue(library.recordShortcut(nil, folder: folder, move: false))
        XCTAssertTrue(library.recordShortcut(valid, folder: folder, move: true))
        XCTAssertNil(library.shortcutError)
    }

    @MainActor
    func testCachedImageDisplaysSynchronously() async throws {
        let folder = try fixtureFolder()
        let url = folder.appendingPathComponent("cached.tiff")
        try makeImage(url)
        let photo = try XCTUnwrap(Catalog.scan([url]).first)
        _ = await ImageLoader.shared.image(photo.url, pixels: max(photo.width, photo.height))
        let view = PhotoScrollView()
        view.load(photo)
        XCTAssertEqual(view.displayedImageURL, photo.url)
    }

    @MainActor
    func testEscapeClosesOverlaysFirst() async {
        let library = Library()
        library.showSettings = true
        library.showInfo = true
        library.exitViewing()
        XCTAssertFalse(library.showSettings)
        XCTAssertTrue(library.showInfo)
        library.exitViewing()
        XCTAssertFalse(library.showInfo)
        library.gallery = false
        library.selected = URL(fileURLWithPath: "/tmp/example.png")
        library.exitViewing()
        XCTAssertTrue(library.gallery)
        XCTAssertNil(library.selected)
        XCTAssertTrue(library.photos.isEmpty)
    }

    @MainActor
    func testRestoredLaunchDoesNotLeaveWelcomeHidden() async throws {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, userInfo: [NSApplication.launchIsDefaultUserInfoKey: false]))
        for _ in 0..<20 {
            if !delegate.library.launching { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(delegate.library.launching)
    }

    @MainActor
    func testDestinationShortcutsAreStableAndRejectDuplicates() async {
        let saved = UserDefaults.standard.object(forKey: "destinationSlots")
        defer { UserDefaults.standard.set(saved, forKey: "destinationSlots") }
        let library = Library()
        library.destinationSlots = [:]
        let first = URL(fileURLWithPath: "/tmp/shortcut-a")
        let second = URL(fileURLWithPath: "/tmp/shortcut-b")
        library.setDestinationSlot(3, for: first)
        library.setDestinationSlot(3, for: second)
        XCTAssertEqual(library.destinationSlots[first.path], 3)
        XCTAssertNil(library.destinationSlots[second.path])
        XCTAssertNotNil(library.error)
        library.destinations = [second, first]
        XCTAssertEqual(library.destinationSlots[first.path], 3)
        XCTAssertEqual(Library().destinationSlots[first.path], 3)
        library.setDestinationSlot(0, for: first)
        XCTAssertNil(library.destinationSlots[first.path])
    }

    @MainActor
    func testSingleFileOpenSelectsImageWithoutGalleryAndResetsFilter() async throws {
        let folder = try fixtureFolder()
        let url = folder.appendingPathComponent("open.tiff")
        try makeImage(url)
        let library = Library()
        library.onlyFavorites = true
        library.open([url])
        XCTAssertFalse(library.gallery)
        XCTAssertFalse(library.onlyFavorites)
        for _ in 0..<200 {
            if !library.busy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(library.busy)
        XCTAssertEqual(library.current?.url, url.resolvingSymlinksInPath())
        XCTAssertNotNil(library.current?.created)
        XCTAssertTrue(library.current?.color.contains("RGB") == true)
    }

    @MainActor
    func testSwitchingClearsOldImageAndOnlyDisplaysLatestRequest() async throws {
        let folder = try fixtureFolder()
        for name in ["one", "two", "three"] { try makeImage(folder.appendingPathComponent("\(name).tiff")) }
        let photos = try Catalog.scan([folder])
        let view = PhotoScrollView()
        view.load(photos[0])
        for _ in 0..<200 {
            if view.displayedImageURL != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(view.displayedImageURL, photos[0].url)
        view.load(photos[1])
        XCTAssertNil(view.displayedImageURL)
        view.load(photos[2])
        for _ in 0..<200 {
            if view.displayedImageURL != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(view.displayedImageURL, photos[2].url)
    }

    private func makeImage(_ url: URL, orientation: Int = 1) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    func testNaturalSortDeduplicatesAndIgnoresInvalidImages() throws {
        let folder = try fixtureFolder()
        let second = folder.appendingPathComponent("照片2.tiff")
        let tenth = folder.appendingPathComponent("照片10.tiff")
        try makeImage(tenth)
        try makeImage(second)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("broken.png"))
        let photos = try Catalog.scan([folder, second])
        XCTAssertEqual(photos.map(\.url), [second, tenth].map { $0.resolvingSymlinksInPath().standardizedFileURL })
        XCTAssertEqual(photos[0].width, 40)
        XCTAssertEqual(photos[0].height, 20)
        XCTAssertGreaterThan(photos[0].bytes, 0)
    }

    func testEXIFOrientationSwapsDimensions() throws {
        let folder = try fixtureFolder()
        try makeImage(folder.appendingPathComponent("portrait.tiff"), orientation: 6)
        let photo = try XCTUnwrap(Catalog.scan([folder]).first)
        XCTAssertEqual(photo.width, 20)
        XCTAssertEqual(photo.height, 40)
        XCTAssertEqual(photo.ratio, 0.5)
    }

    func testDoesNotRecursivelyScanDirectories() throws {
        let folder = try fixtureFolder()
        let child = folder.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try makeImage(child.appendingPathComponent("photo.tiff"))
        XCTAssertTrue(try Catalog.scan([folder]).isEmpty)
        XCTAssertEqual(try Catalog.scan([child]).count, 1)
    }

    func testMissingFolderReportsFailure() {
        XCTAssertThrowsError(try Catalog.scan([URL(fileURLWithPath: "/GuoguoKan-nonexistent-\(UUID().uuidString)")]))
    }

    func testLoaderAppliesOrientationAndDownsampling() async throws {
        let folder = try fixtureFolder()
        let url = folder.appendingPathComponent("rotated.tiff")
        try makeImage(url, orientation: 6)
        let loaded = await ImageLoader.shared.image(url, pixels: 20)
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.width, 10)
        XCTAssertEqual(image.height, 20)
        let missing = await ImageLoader.shared.image(folder.appendingPathComponent("missing.png"), pixels: 20)
        XCTAssertNil(missing)
    }
}
