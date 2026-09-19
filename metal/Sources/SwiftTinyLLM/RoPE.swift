// Sources/SwiftLLM/RoPE.swift

import Foundation

struct RotaryEmbedding: Sendable {
    let headDimension: Int
    let base: Float

    init(headDimension: Int, base: Float = 10_000) {
        precondition(headDimension % 2 == 0)
        self.headDimension = headDimension
        self.base          = base
    }

    func apply(_ vector: inout [Float], position: Int) {
        precondition(vector.count == headDimension)
        let half = headDimension / 2
        for pair in 0..<half {
            let i         = pair * 2
            let exponent  = Float(i) / Float(headDimension)
            let frequency = 1 / pow(base, exponent)
            let angle     = Float(position) * frequency
            let cosine    = cos(angle)
            let sine      = sin(angle)
            let x0        = vector[i]
            let x1        = vector[i + 1]
            vector[i]     = x0 * cosine - x1 * sine
            vector[i + 1] = x0 * sine   + x1 * cosine
        }
    }
}
