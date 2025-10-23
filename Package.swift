// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FFWF",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FFWF", targets: ["FFWF"])
    ],
    targets: [
        .executableTarget(
            name: "FFWF",
            path: "Sources"
        )
    ]
)
