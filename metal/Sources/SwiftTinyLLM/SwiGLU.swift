// Sources/SwiftLLM/SwiGLU.swift

import Foundation

struct SwiGLU: Sendable {
    var gateProjection: Tensor
    var upProjection:   Tensor
    var downProjection: Tensor

    init(
        modelDimension: Int,
        hiddenDimension: Int,
        generator: inout SplitMix64
    ) {
        gateProjection = Tensor.random(
            shape: [modelDimension, hiddenDimension], using: &generator)
        upProjection   = Tensor.random(
            shape: [modelDimension, hiddenDimension], using: &generator)
        downProjection = Tensor.random(
            shape: [hiddenDimension, modelDimension], using: &generator)
    }

    @inline(__always)
    private func silu(_ x: Float) -> Float {
        x / (1 + exp(-x))
    }

    func forward(_ input: Tensor) -> Tensor {
        let gate = input.matrixMultiplied(by: gateProjection)
        let up   = input.matrixMultiplied(by: upProjection)
        precondition(gate.shape == up.shape)

        var activated = Tensor.zeros(gate.shape)
        for index in 0..<gate.count {
            activated[index] = silu(gate[index]) * up[index]
        }
        return activated.matrixMultiplied(by: downProjection)
    }
}
