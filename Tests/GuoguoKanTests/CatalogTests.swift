import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import GuoguoKan

final class CatalogTests: XCTestCase {
    private func fixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GuoguoKanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
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
