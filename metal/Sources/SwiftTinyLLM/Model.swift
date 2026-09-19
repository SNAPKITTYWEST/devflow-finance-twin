import Foundation

struct ModelConfig: Codable, Sendable {
    var vocabSize = 258
    var dModel = 96
    var layers = 4
    var heads = 4
    var dFF = 256
    var context = 256
    var seed: UInt64 = 0x53574946544C4C4D

    var headDim: Int { dModel / heads }
    func validate() {
        precondition(dModel % heads == 0)
        precondition(headDim % 2 == 0, "RoPE requires even head dimension")
    }
}

struct Linear: Codable, Sendable {
    let input: Int
    let output: Int
    var weight: [Float]
    var bias: [Float]

    init(input: Int, output: Int, rng: inout SplitMix64, scale: Float? = nil, bias: Bool = false) {
        self.input = input; self.output = output
        let s = scale ?? (1 / sqrt(Float(input)))
        self.weight = (0..<(input * output)).map { _ in rng.normal(std: s) }
        self.bias = bias ? Array(repeating: 0, count: output) : []
    }

    func callAsFunction(_ x: [Float]) -> [Float] {
        var y = Math.matVec(weight, rows: output, cols: input, x)
        if !bias.isEmpty { for i in y.indices { y[i] += bias[i] } }
        return y
    }
}

struct RMSNormLayer: Codable, Sendable {
    var weight: [Float]
    init(size: Int) { weight = Array(repeating: 1, count: size) }
    func callAsFunction(_ x: [Float]) -> [Float] { Math.rmsNorm(x, weight: weight) }
}

struct Attention: Codable, Sendable {
    let dModel: Int, heads: Int, headDim: Int
    var qProj: Linear, kProj: Linear, vProj: Linear, oProj: Linear

    init(config: ModelConfig, rng: inout SplitMix64) {
        dModel = config.dModel; heads = config.heads; headDim = config.headDim
        qProj = Linear(input: dModel, output: dModel, rng: &rng)
        kProj = Linear(input: dModel, output: dModel, rng: &rng)
        vProj = Linear(input: dModel, output: dModel, rng: &rng)
        oProj = Linear(input: dModel, output: dModel, rng: &rng, scale: 1 / sqrt(Float(dModel * max(1, config.layers))))
    }

    func forward(_ states: [[Float]]) -> [[Float]] {
        let n = states.count
        guard n > 0 else { return [] }
        var qs = Array(repeating: Array(repeating: Float(0), count: dModel), count: n)
        var ks = qs, vs = qs

        for t in 0..<n {
            qs[t] = qProj(states[t]); ks[t] = kProj(states[t]); vs[t] = vProj(states[t])
            for h in 0..<heads {
                let lo = h * headDim, hi = lo + headDim
                var qh = Array(qs[t][lo..<hi]); var kh = Array(ks[t][lo..<hi])
                Math.rope(&qh, position: t); Math.rope(&kh, position: t)
                qs[t].replaceSubrange(lo..<hi, with: qh); ks[t].replaceSubrange(lo..<hi, with: kh)
            }
        }

        var result = Array(repeating: Array(repeating: Float(0), count: dModel), count: n)
        let scale = 1 / sqrt(Float(headDim))
        for t in 0..<n {
            var merged = Array(repeating: Float(0), count: dModel)
            for h in 0..<heads {
                let base = h * headDim
                var scores = Array(repeating: Float(0), count: t + 1)
                for j in 0...t { scores[j] = Math.dot(qs[t], base, ks[j], base, headDim) * scale }
                let probs = Math.softmax(scores)
                for j in 0...t {
                    let p = probs[j]
                    for d in 0..<headDim { merged[base+d] += p * vs[j][base+d] }
                }
            }
            result[t] = oProj(merged)
        }
        return result
    }
}

struct FeedForward: Codable, Sendable {
    var gate: Linear, up: Linear, down: Linear
    init(config: ModelConfig, rng: inout SplitMix64) {
        gate = Linear(input: config.dModel, output: config.dFF, rng: &rng)
        up = Linear(input: config.dModel, output: config.dFF, rng: &rng)
        down = Linear(input: config.dFF, output: config.dModel, rng: &rng, scale: 1 / sqrt(Float(config.dFF * max(1, config.layers))))
    }
    func forward(_ x: [Float]) -> [Float] {
        let g = gate(x), u = up(x)
        var z = Array(repeating: Float(0), count: g.count)
        for i in z.indices { z[i] = Math.silu(g[i]) * u[i] }
        return down(z)
    }
}

struct TransformerBlock: Codable, Sendable {
    var attnNorm: RMSNormLayer
    var attention: Attention
    var ffnNorm: RMSNormLayer
    var ffn: FeedForward

    init(config: ModelConfig, rng: inout SplitMix64) {
        attnNorm = RMSNormLayer(size: config.dModel)
        attention = Attention(config: config, rng: &rng)
        ffnNorm = RMSNormLayer(size: config.dModel)
        ffn = FeedForward(config: config, rng: &rng)
    }

    func forward(_ x: [[Float]]) -> [[Float]] {
        let normalized = x.map { attnNorm($0) }
        let attended = attention.forward(normalized)
        var residual = x
        for t in residual.indices { for d in residual[t].indices { residual[t][d] += attended[t][d] } }
        var out = residual
        for t in out.indices {
            let delta = ffn.forward(ffnNorm(residual[t]))
            for d in out[t].indices { out[t][d] += delta[d] }
        }
        return out
    }
}

struct TinyTransformer: Codable, Sendable {
    var config: ModelConfig
    var tokenEmbedding: [Float]
    var blocks: [TransformerBlock]
    var finalNorm: RMSNormLayer

    init(config: ModelConfig = ModelConfig()) {
        config.validate()
        self.config = config
        var rng = SplitMix64(seed: config.seed)
        tokenEmbedding = (0..<(config.vocabSize * config.dModel)).map { _ in rng.normal(std: 0.02) }
        blocks = (0..<config.layers).map { _ in TransformerBlock(config: config, rng: &rng) }
        finalNorm = RMSNormLayer(size: config.dModel)
    }

    var parameterCount: Int {
        var n = tokenEmbedding.count + finalNorm.weight.count
        for b in blocks {
            n += b.attnNorm.weight.count + b.ffnNorm.weight.count
            let linears = [b.attention.qProj,b.attention.kProj,b.attention.vProj,b.attention.oProj,b.ffn.gate,b.ffn.up,b.ffn.down]
            for l in linears { n += l.weight.count + l.bias.count }
        }
        return n
    }

    func embedding(_ token: Int) -> [Float] {
        let t = max(0, min(config.vocabSize - 1, token))
        let start = t * config.dModel
        return Array(tokenEmbedding[start..<(start + config.dModel)])
    }

    func logits(for tokens: [Int]) -> [Float] {
        let clipped = Array(tokens.suffix(config.context))
        var x = clipped.map(embedding)
        for block in blocks { x = block.forward(x) }
        guard let last = x.last else { return Array(repeating: 0, count: config.vocabSize) }
        let h = finalNorm(last)
        var logits = Array(repeating: Float(0), count: config.vocabSize)
        for token in 0..<config.vocabSize {
            logits[token] = Math.dot(tokenEmbedding, token * config.dModel, h, 0, config.dModel)
        }
        return logits
    }

    func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> TinyTransformer {
        try JSONDecoder().decode(TinyTransformer.self, from: Data(contentsOf: url))
    }
}

struct ModelInfo: Codable, Sendable {
    let parameters: Int
    let layers: Int
    let dModel: Int
    let heads: Int
    let context: Int
    let vocab: Int
}

actor ModelEngine {
    private var model: TinyTransformer
    private let tokenizer = ByteTokenizer()

    init(model: TinyTransformer) { self.model = model }

    func info() -> ModelInfo {
        ModelInfo(parameters: model.parameterCount, layers: model.config.layers, dModel: model.config.dModel,
                  heads: model.config.heads, context: model.config.context, vocab: model.config.vocabSize)
    }

    func generate(prompt: String, maxTokens: Int, temperature: Float, topK: Int, topP: Float, seed: UInt64) -> String {
        var tokens = tokenizer.encode(prompt)
        var generated: [Int] = []
        var sampler = Sampler(seed: seed)
        for _ in 0..<max(1, min(maxTokens, 512)) {
            let logits = model.logits(for: tokens)
            let next = sampler.sample(logits: logits, temperature: temperature, topK: topK, topP: topP)
            if next == tokenizer.eos { break }
            tokens.append(next); generated.append(next)
        }
        return tokenizer.decode(generated)
    }
}
