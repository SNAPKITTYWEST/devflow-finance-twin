# Apple Silicon raw Metal target

products: [
    .executable(name: "MetalTransformer", targets: ["MetalTransformer"])
]

targets: [
    .executableTarget(
        name: "MetalTransformer",
        path: "Sources/MetalTransformer",
        resources: [.copy("Transformer.metal")]
    ),
    .testTarget(name: "MetalTransformerTests", dependencies: ["MetalTransformer"], path: "Tests")
]
