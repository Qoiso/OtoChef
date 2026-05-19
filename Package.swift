// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OtoChef",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OtoChef", targets: ["OtoChefApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OtoChefApp",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/OtoChefApp"
        ),
        .testTarget(
            name: "OtoChefAppTests",
            dependencies: ["OtoChefApp"],
            path: "Tests/OtoChefAppTests"
        )
    ]
)
