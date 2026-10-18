import AppKit
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for index in 1...8 {
    let width = index % 3 == 0 ? 640 : 1200
    let height = index % 3 == 0 ? 1600 : (index % 2 == 0 ? 800 : 1100)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let start = NSColor(calibratedHue: CGFloat(index) / 10, saturation: 0.48, brightness: 0.75, alpha: 1).cgColor
    let end = NSColor(calibratedHue: CGFloat(index) / 10 + 0.12, saturation: 0.7, brightness: 0.28, alpha: 1).cgColor
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [start, end] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    context.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    context.fillEllipse(in: CGRect(x: width / 4, y: height / 3, width: width / 2, height: width / 2))
    let image = context.makeImage()!
    let target = destination.appendingPathComponent("示例\(index).png")
    let writer = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { fatalError("无法写入示例") }
}
print("已生成 8 张测试图片")
