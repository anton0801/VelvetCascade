// swift-tools-version:5.9
import PackageDescription

// VelvetCore: чистый Domain-движок Velvet Cascade (без SwiftUI/SpriteKit),
// инструмент LevelForge (генерация/решение/валидация 180 уровней) и unit-тесты.
let package = Package(
    name: "VelvetCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "VelvetDomain", targets: ["VelvetDomain"]),
    ],
    targets: [
        .target(name: "VelvetDomain"),
        .executableTarget(
            name: "LevelForge",
            dependencies: ["VelvetDomain"],
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .testTarget(name: "VelvetDomainTests", dependencies: ["VelvetDomain"]),
    ]
)
