import PackageDescription

let package = Package(
    name: "MetalTransformer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalTransformer",  targets: ["MetalTransformer"]),
        .executable(name: "swift-tiny-llm", targets: ["SwiftTinyLLM"]),
    ],
    targets: [
        .target(
            name: "MetalTransformer",
            path: "Sources/MetalTransformer",
            resources: [.copy("Transformer.metal")]
        ),
        .executableTarget(
            name: "SwiftTinyLLM",
            path: "Sources/SwiftTinyLLM"
        ),
        .testTarget(
            name: "MetalTransformerTests",
            dependencies: ["MetalTransformer"],
            path: "Tests"
        ),
    ]
)
