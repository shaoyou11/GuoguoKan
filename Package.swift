// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GuoguoKan",
    platforms: [.macOS("27.0")],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "GuoguoKan", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "GuoguoKanTests", dependencies: ["GuoguoKan"])
    ]
)
