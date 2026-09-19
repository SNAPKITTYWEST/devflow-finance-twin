// Sources/SwiftLLM/Tensor.swift

import Foundation

enum TensorError: Error {
    case invalidShape
    case incompatibleShapes
    case indexOutOfBounds
}

struct Tensor: Sendable {
    private(set) var values: [Float]
    let shape: [Int]

    init(_ values: [Float], shape: [Int]) {
        precondition(!shape.isEmpty)
        precondition(shape.allSatisfy { $0 > 0 })
        let expected = shape.reduce(1, *)
        precondition(expected == values.count)
        self.values = values
        self.shape  = shape
    }

    init(repeating value: Float, shape: [Int]) {
        precondition(!shape.isEmpty)
        let count   = shape.reduce(1, *)
        self.values = Array(repeating: value, count: count)
        self.shape  = shape
    }

    static func zeros(_ shape: [Int]) -> Tensor { Tensor(repeating: 0, shape: shape) }
    static func ones (_ shape: [Int]) -> Tensor { Tensor(repeating: 1, shape: shape) }

    static func random(
        shape: [Int],
        scale: Float = 0.02,
        using generator: inout some RandomNumberGenerator
    ) -> Tensor {
        let count = shape.reduce(1, *)
        var data  = [Float]()
        data.reserveCapacity(count)
        for _ in 0..<count {
            let u1 = max(Float.random(in: 0..<1, using: &generator),
                         Float.leastNonzeroMagnitude)
            let u2 = Float.random(in: 0..<1, using: &generator)
            data.append(sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2) * scale)
        }
        return Tensor(data, shape: shape)
    }

    var count: Int { values.count }
    var rank:  Int { shape.count  }

    subscript(_ index: Int) -> Float {
        get { precondition(index >= 0 && index < values.count); return values[index] }
        set { precondition(index >= 0 && index < values.count); values[index] = newValue }
    }

    subscript(_ row: Int, _ column: Int) -> Float {
        get {
            precondition(shape.count == 2)
            let cols = shape[1]
            precondition(row >= 0 && row < shape[0])
            precondition(column >= 0 && column < cols)
            return values[row * cols + column]
        }
        set {
            precondition(shape.count == 2)
            let cols = shape[1]
            precondition(row >= 0 && row < shape[0])
            precondition(column >= 0 && column < cols)
            values[row * cols + column] = newValue
        }
    }

    mutating func fill(_ value: Float) {
        for index in values.indices { values[index] = value }
    }

    func map(_ transform: (Float) -> Float) -> Tensor {
        Tensor(values.map(transform), shape: shape)
    }

    func adding(_ other: Tensor) -> Tensor {
        precondition(shape == other.shape)
        var result = values
        for index in result.indices { result[index] += other.values[index] }
        return Tensor(result, shape: shape)
    }

    func multiplying(_ scalar: Float) -> Tensor {
        Tensor(values.map { $0 * scalar }, shape: shape)
    }

    func elementwiseMultiplying(_ other: Tensor) -> Tensor {
        precondition(shape == other.shape)
        var result = [Float](repeating: 0, count: count)
        for index in result.indices { result[index] = values[index] * other.values[index] }
        return Tensor(result, shape: shape)
    }
}

// MARK: - Matrix operations

extension Tensor {
    func matrixMultiplied(by other: Tensor) -> Tensor {
        precondition(rank == 2)
        precondition(other.rank == 2)
        let m = shape[0], k = shape[1]
        precondition(other.shape[0] == k)
        let n = other.shape[1]
        var output = [Float](repeating: 0, count: m * n)
        for row in 0..<m {
            let lhsBase    = row * k
            let outputBase = row * n
            for inner in 0..<k {
                let lhs    = values[lhsBase + inner]
                let rhsBase = inner * n
                for column in 0..<n {
                    output[outputBase + column] += lhs * other.values[rhsBase + column]
                }
            }
        }
        return Tensor(output, shape: [m, n])
    }

    func transposed() -> Tensor {
        precondition(rank == 2)
        let rows = shape[0], columns = shape[1]
        var output = [Float](repeating: 0, count: count)
        for row in 0..<rows {
            for column in 0..<columns {
                output[column * rows + row] = values[row * columns + column]
            }
        }
        return Tensor(output, shape: [columns, rows])
    }

    func row(_ index: Int) -> Tensor {
        precondition(rank == 2)
        let columns = shape[1]
        precondition(index >= 0 && index < shape[0])
        let start = index * columns
        return Tensor(Array(values[start..<start + columns]), shape: [1, columns])
    }
}
