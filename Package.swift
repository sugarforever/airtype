// swift-tools-version:5.9
import PackageDescription
import Foundation

let coreTestsOnly = ProcessInfo.processInfo.environment["AIRTYPE_CORE_TESTS"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
]

var products: [Product] = [
    .library(name: "CorrectionLearningCore", targets: ["CorrectionLearningCore"]),
    .library(name: "VocabularyCore", targets: ["VocabularyCore"]),
    .library(name: "DashboardCore", targets: ["DashboardCore"])
]

var targets: [Target] = [
    .target(
        name: "CorrectionLearningCore",
        path: "Sources/CorrectionLearning",
        linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .target(
        name: "VocabularyCore",
        path: "Sources/VocabularyCore",
        linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .target(
        name: "DashboardCore",
        dependencies: ["VocabularyCore"],
        path: "Sources/DashboardCore"
    ),
    .testTarget(
        name: "AirtypeTests",
        dependencies: coreTestsOnly
            ? ["CorrectionLearningCore"]
            : ["CorrectionLearningCore", "Airtype"],
        path: "Tests/AirtypeTests"
    ),
    .testTarget(
        name: "VocabularyCoreTests",
        dependencies: ["VocabularyCore"],
        path: "Tests/VocabularyCoreTests"
    ),
    .testTarget(
        name: "DashboardCoreTests",
        dependencies: ["DashboardCore", "VocabularyCore"],
        path: "Tests/DashboardCoreTests"
    )
]

if !coreTestsOnly {
    packageDependencies.append(.package(
        url: "https://github.com/Blaizzy/mlx-audio-swift.git",
        revision: "cae704f53bc32a3d0b606823828fbc5bedaaf388"
    ))
    products.append(.executable(name: "Airtype", targets: ["Airtype"]))
    targets.insert(
        .executableTarget(
            name: "Airtype",
            dependencies: [
                "HotKey",
                "CorrectionLearningCore",
                "VocabularyCore",
                "DashboardCore",
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift")
            ],
            path: "Sources",
            exclude: [
                "Assets.xcassets",
                "CorrectionLearning",
                "DashboardCore",
                "Services/GLMASRAdapter.swift",
                "VocabularyCore"
            ]
        ),
        at: 0
    )
}

let package = Package(
    name: "Airtype",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: packageDependencies,
    targets: targets
)
