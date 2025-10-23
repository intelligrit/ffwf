// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FFFW",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FFFW", targets: ["FFFW"])
    ],
    targets: [
        .executableTarget(
            name: "FFFW",
            path: "Sources"
        )
    ]
)
