// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Touchless",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Touchless", targets: ["Touchless"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Touchless",
            dependencies: ["HotKey"],
            path: "Sources"
        )
    ]
)
