import PackageDescription

let package = Package(
    name: "MetalTransformer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MetalTransformer", targets: ["MetalTransformer"])],
    targets: [
        .target(name: "MetalTransformer", path: "Sources/MetalTransformer", resources: [.copy("Transformer.metal")]),
        .testTarget(name: "MetalTransformerTests", dependencies: ["MetalTransformer"], path: "Tests")
    ]
)
