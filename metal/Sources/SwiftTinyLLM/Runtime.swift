import Foundation

struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53))
    }
    mutating func normal(std: Float = 1) -> Float {
        let u1 = max(uniform(), 1e-7)
        let u2 = uniform()
        let r = sqrt(-2 * log(u1))
        return std * r * cos(2 * Float.pi * u2)
    }
}

enum Math {
    @inline(__always) static func dot(_ a: [Float], _ a0: Int, _ b: [Float], _ b0: Int, _ n: Int) -> Float {
        var s: Float = 0
        var i = 0
        while i < n { s += a[a0+i] * b[b0+i]; i += 1 }
        return s
    }

    static func matVec(_ matrix: [Float], rows: Int, cols: Int, _ x: [Float]) -> [Float] {
        precondition(x.count == cols && matrix.count == rows * cols)
        var y = Array(repeating: Float(0), count: rows)
        for r in 0..<rows {
            var s: Float = 0
            let base = r * cols
            for c in 0..<cols { s += matrix[base+c] * x[c] }
            y[r] = s
        }
        return y
    }

    static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        precondition(a.count == b.count)
        var out = a
        for i in out.indices { out[i] += b[i] }
        return out
    }

    static func rmsNorm(_ x: [Float], weight: [Float], eps: Float = 1e-5) -> [Float] {
        precondition(x.count == weight.count)
        var ss: Float = 0
        for v in x { ss += v * v }
        let inv = 1 / sqrt(ss / Float(x.count) + eps)
        var y = Array(repeating: Float(0), count: x.count)
        for i in x.indices { y[i] = x[i] * inv * weight[i] }
        return y
    }

    @inline(__always) static func silu(_ x: Float) -> Float { x / (1 + exp(-x)) }

    static func softmax(_ x: [Float]) -> [Float] {
        guard let m = x.max() else { return [] }
        var out = Array(repeating: Float(0), count: x.count)
        var sum: Float = 0
        for i in x.indices { out[i] = exp(x[i] - m); sum += out[i] }
        if sum <= 0 || !sum.isFinite { return Array(repeating: 1 / Float(max(1, x.count)), count: x.count) }
        for i in out.indices { out[i] /= sum }
        return out
    }

    static func rope(_ vector: inout [Float], position: Int, base: Float = 10_000) {
        let half = vector.count / 2
        guard half > 0 else { return }
        for i in 0..<half {
            let theta = Float(position) / pow(base, Float(2 * i) / Float(vector.count))
            let c = cos(theta), s = sin(theta)
            let a = vector[2*i], b = vector[2*i+1]
            vector[2*i] = a * c - b * s
            vector[2*i+1] = a * s + b * c
        }
    }
}

struct ByteTokenizer: Sendable {
    let bos = 256
    let eos = 257
    let vocabSize = 258

    func encode(_ text: String, addBOS: Bool = true) -> [Int] {
        var out: [Int] = addBOS ? [bos] : []
        out.append(contentsOf: text.utf8.map(Int.init))
        return out
    }

    func decode(_ tokens: [Int]) -> String {
        let bytes = tokens.compactMap { t -> UInt8? in
            guard (0..<256).contains(t) else { return nil }
            return UInt8(t)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct Sampler: Sendable {
    var rng: SplitMix64
    init(seed: UInt64) { rng = SplitMix64(seed: seed) }

    mutating func sample(logits: [Float], temperature: Float, topK: Int, topP: Float) -> Int {
        if temperature <= 0 {
            return logits.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        }
        let scaled = logits.map { $0 / max(temperature, 1e-4) }
        var ranked = scaled.enumerated().sorted { $0.element > $1.element }
        if topK > 0 && ranked.count > topK { ranked.removeSubrange(topK...) }
        let probs = Math.softmax(ranked.map(\.element))
        var pairs = zip(ranked.map(\.offset), probs).map { ($0, $1) }
        if topP < 1 {
            var cumulative: Float = 0
            var keep = 0
            for (_, p) in pairs {
                cumulative += p; keep += 1
                if cumulative >= topP { break }
            }
            pairs = Array(pairs.prefix(max(1, keep)))
        }
        let total = pairs.reduce(Float(0)) { $0 + $1.1 }
        var draw = rng.uniform() * total
        for (token, p) in pairs {
            draw -= p
            if draw <= 0 { return token }
        }
        return pairs.last?.0 ?? 0
    }
}
