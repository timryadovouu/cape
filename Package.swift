// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacNotch",
    platforms: [.macOS(.v13)],
    dependencies: [
        // On-device speech-to-text (Whisper via CoreML). Provides the `WhisperKit`
        // product; downloads the model on first use.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacNotch",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/MacNotch"
        )
    ]
)
