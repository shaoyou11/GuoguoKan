// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GuoguoKan",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "GuoguoKan"),
        .testTarget(name: "GuoguoKanTests", dependencies: ["GuoguoKan"])
    ]
)
