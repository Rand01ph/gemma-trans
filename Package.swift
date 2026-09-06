// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gemma-trans",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "GemmaTransKit", targets: ["GemmaTransKit"]),
        .library(name: "GemmaTransServer", targets: ["GemmaTransServer"]),
        .executable(name: "gemma-trans-cli", targets: ["gemma-trans-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .binaryTarget(
            name: "LlamaRuntime",
            url: "https://github.com/Rand01ph/gemma-trans/releases/download/runtime-llama-2.2.0-r1/LlamaRuntime-2.2.0-r1.zip",
            checksum: "58dcad403e81b6e82d43aa2c87d0c35c4b21c620563ebe892dc34f25a1e6130f"
        ),
        .target(
            name: "GemmaTransKit",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .target(name: "LlamaRuntime", condition: .when(platforms: [.macOS])),
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
        .testTarget(
            name: "GemmaTransKitTests",
            dependencies: ["GemmaTransKit"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(name: "GemmaTransServerTests", dependencies: ["GemmaTransServer"]),
    ]
)
