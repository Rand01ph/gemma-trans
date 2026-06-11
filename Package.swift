// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gemma-trans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GemmaTransKit", targets: ["GemmaTransKit"]),
        .library(name: "GemmaTransServer", targets: ["GemmaTransServer"]),
        .executable(name: "gemma-trans-cli", targets: ["gemma-trans-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GemmaTransKit",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .target(
            name: "GemmaTransServer",
            dependencies: [
                "GemmaTransKit",
                .product(name: "FlyingFox", package: "FlyingFox"),
                .product(name: "FlyingSocks", package: "FlyingFox"),
            ]
        ),
        .executableTarget(
            name: "gemma-trans-cli",
            dependencies: ["GemmaTransKit", "GemmaTransServer"]
        ),
        .testTarget(name: "GemmaTransKitTests", dependencies: ["GemmaTransKit"]),
        .testTarget(name: "GemmaTransServerTests", dependencies: ["GemmaTransServer"]),
    ]
)
