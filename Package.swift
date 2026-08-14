// swift-tools-version:5.9
import PackageDescription
import Foundation

let coreTestsOnly = ProcessInfo.processInfo.environment["AIRTYPE_CORE_TESTS"] == "1"

var products: [Product] = [
    .library(name: "CorrectionLearningCore", targets: ["CorrectionLearningCore"]),
    .library(name: "VocabularyCore", targets: ["VocabularyCore"])
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
    .testTarget(
        name: "AirtypeTests",
        dependencies: ["CorrectionLearningCore"],
        path: "Tests/AirtypeTests"
    ),
    .testTarget(
        name: "VocabularyCoreTests",
        dependencies: ["VocabularyCore"],
        path: "Tests/VocabularyCoreTests"
    )
]

if !coreTestsOnly {
    products.append(.executable(name: "Airtype", targets: ["Airtype"]))
    targets.insert(
        .executableTarget(
            name: "Airtype",
            dependencies: ["HotKey", "CorrectionLearningCore", "VocabularyCore"],
            path: "Sources",
            exclude: ["CorrectionLearning", "VocabularyCore"]
        ),
        at: 0
    )
}

let package = Package(
    name: "Airtype",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: targets
)
