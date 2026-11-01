// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawdPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClawdPet", targets: ["ClawdPet"])
    ],
    targets: [
        .executableTarget(
            name: "ClawdPet",
            dependencies: [],
            path: "Sources/ClawdPet"
        )
    ]
)
