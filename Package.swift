// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteStream",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NoteStreamCore",
            targets: ["NoteStreamCore"]
        ),
        .library(
            name: "NoteStreamInfrastructure",
            targets: ["NoteStreamInfrastructure"]
        ),
        .executable(
            name: "NoteStreamApp",
            targets: ["NoteStreamApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "6.3.1")
    ],
    targets: [
        .target(
            name: "NoteStreamCore",
            dependencies: []
        ),
        .target(
            name: "NoteStreamInfrastructure",
            dependencies: [
                "NoteStreamCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .executableTarget(
            name: "NoteStreamApp",
            dependencies: [
                "NoteStreamCore",
                "NoteStreamInfrastructure",
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NoteStreamCoreTests",
            dependencies: [
                "NoteStreamCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "NoteStreamInfrastructureTests",
            dependencies: [
                "NoteStreamCore",
                "NoteStreamInfrastructure",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)

