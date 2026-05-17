// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OtoChef",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OtoChef", targets: ["OtoChefApp"])
    ],
    targets: [
        .executableTarget(
            name: "OtoChefApp",
            path: "Sources/OtoChefApp"
        ),
        .testTarget(
            name: "OtoChefAppTests",
            dependencies: ["OtoChefApp"],
            path: "Tests/OtoChefAppTests"
        )
    ]
)
