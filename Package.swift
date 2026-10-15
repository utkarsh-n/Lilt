// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiltCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "LiltCore", targets: ["LiltCore"])],
    targets: [
        .target(name: "LiltCore"),
        .testTarget(name: "LiltCoreTests", dependencies: ["LiltCore"]),
        .target(name: "LiltPersistence", dependencies: ["LiltCore"], path: "App/Models",
                exclude: ["GameSession.swift"], sources: ["StoredMaze.swift", "RunPersistence.swift"]),
        .testTarget(name: "LiltPersistenceTests", dependencies: ["LiltCore", "LiltPersistence"])
    ]
)
