// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cp2077-patcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cp2077-patcher", targets: ["cp2077-patcher"]),
        .executable(name: "CP2077 Mac Archive Patcher", targets: ["CP2077MacArchivePatcherApp"]),
        .library(name: "CP2077ArchiveCore", targets: ["CP2077ArchiveCore"]),
    ],
    targets: [
        .target(
            name: "CP2077ArchiveCore"
        ),
        .executableTarget(
            name: "cp2077-patcher",
            dependencies: ["CP2077ArchiveCore"]
        ),
        .executableTarget(
            name: "CP2077MacArchivePatcherApp",
            dependencies: ["CP2077ArchiveCore"]
        ),
        .testTarget(
            name: "CP2077ArchiveCoreTests",
            dependencies: ["CP2077ArchiveCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
