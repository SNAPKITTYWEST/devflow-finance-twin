import Foundation
import Metal

public struct TransformerDimensions { public var hidden=3072, intermediate=8192, heads=24, kvHeads=8, headDim=128, vocab=32000, context=4096 }

public final class MetalTransformer {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [String: MTLComputePipelineState] = [:]
    public let dimensions: TransformerDimensions

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), dimensions: TransformerDimensions = .init()) throws {
        guard let device else { throw NSError(domain: "MetalTransformer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"]) }
        self.device = device; self.dimensions = dimensions
        guard let queue = device.makeCommandQueue() else { throw NSError(domain: "MetalTransformer", code: 2, userInfo: nil) }
        self.queue = queue
        guard let url = Bundle.module.url(forResource: "Transformer", withExtension: "metal") else { throw NSError(domain: "MetalTransformer", code: 3, userInfo: nil) }
        self.library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
        for name in ["embedding","rmsnorm","rope","qmatvec_i4","qkv_projection_i4","attention_scores","causal_softmax","attention_times_v","swiglu","residual_add","output_projection_i4","copy_kv","final_normalization"] {
            guard let f=library.makeFunction(name: name) else { throw NSError(domain: "MetalTransformer", code: 4, userInfo: [NSLocalizedDescriptionKey: name]) }
            pipelines[name] = try device.makeComputePipelineState(function: f)
        }
    }

    private func dispatch(_ name: String, buffers: [MTLBuffer?], count: Int) throws -> MTLCommandBuffer {
        guard let p=pipelines[name], let cb=queue.makeCommandBuffer(), let e=cb.makeComputeCommandEncoder() else { throw NSError(domain: "MetalTransformer", code: 5, userInfo: nil) }
        e.setComputePipelineState(p); for (i,b) in buffers.enumerated(){e.setBuffer(b, offset: 0, index: i)}
        let width=max(1,min(p.maxTotalThreadsPerThreadgroup, count)); e.dispatchThreads(MTLSize(width: count,height: 1,depth: 1), threadsPerThreadgroup: MTLSize(width: width,height: 1,depth: 1)); e.endEncoding(); return cb
    }

    public func encodeToken(token: MTLBuffer, embedding: MTLBuffer, output: MTLBuffer) throws {
        var d=dimensions
        guard let p=pipelines["embedding"], let cb=queue.makeCommandBuffer(), let e=cb.makeComputeCommandEncoder() else { throw NSError(domain: "MetalTransformer", code: 6, userInfo: nil) }
        e.setComputePipelineState(p); e.setBuffer(embedding, offset: 0, index: 0); e.setBuffer(token, offset: 0, index: 1); e.setBuffer(output, offset: 0, index: 2); e.setBytes(&d, length: MemoryLayout.size(ofValue: d), index: 3)
        e.dispatchThreads(MTLSize(width: d.hidden,height: 1,depth: 1), threadsPerThreadgroup: MTLSize(width: min(p.maxTotalThreadsPerThreadgroup,d.hidden),height: 1,depth: 1)); e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    }

    public func greedyToken(from logits: MTLBuffer, count: Int) -> UInt32 { let p=logits.contents().bindMemory(to: Float16.self, capacity: count); var best=0; var value = -Float.infinity; for i in 0..<count { let v=Float(p[i]); if v > value { value=v; best=i } }; return UInt32(best) }
}
