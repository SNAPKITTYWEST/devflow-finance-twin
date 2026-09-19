// Sources/SwiftLLM/RMSNorm.swift

import Foundation

struct RMSNorm: Sendable {
    var weight: Tensor
    let epsilon: Float

    init(dimension: Int, epsilon: Float = 1e-5) {
        self.weight  = .ones([dimension])
        self.epsilon = epsilon
    }

    func forward(_ input: Tensor) -> Tensor {
        precondition(input.rank == 2)
        precondition(input.shape[1] == weight.count)

        let rows    = input.shape[0]
        let columns = input.shape[1]
        var output  = Tensor.zeros([rows, columns])

        for row in 0..<rows {
            var squareSum: Float = 0
            for column in 0..<columns {
                let v = input[row, column]
                squareSum += v * v
            }
            let inverseRMS = 1 / sqrt(squareSum / Float(columns) + epsilon)
            for column in 0..<columns {
                output[row, column] =
                    input[row, column] * inverseRMS * weight[column]
            }
        }
        return output
    }
}
