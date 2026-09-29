// swift-tools-version: 5.9
// ArtForge — procedural CoreGraphics art pipeline for Velvet Cascade (VC01–VC40).
import PackageDescription

let package = Package(
    name: "ArtForge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ArtForge",
            path: "Sources/ArtForge"
        )
    ]
)
