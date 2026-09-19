// Sources/SwiftLLM/ModelConfig.swift

import Foundation

struct ModelConfig: Codable, Sendable {
    let vocabularySize: Int
    let contextLength: Int
    let modelDimension: Int
    let hiddenDimension: Int
    let layerCount: Int
    let headCount: Int
    let headDimension: Int

    init(
        vocabularySize: Int = 256,
        contextLength: Int = 512,
        modelDimension: Int = 192,
        hiddenDimension: Int = 512,
        layerCount: Int = 6,
        headCount: Int = 6
    ) {
        precondition(vocabularySize > 0)
        precondition(contextLength > 0)
        precondition(modelDimension > 0)
        precondition(hiddenDimension > 0)
        precondition(layerCount > 0)
        precondition(headCount > 0)
        precondition(modelDimension % headCount == 0)

        self.vocabularySize   = vocabularySize
        self.contextLength    = contextLength
        self.modelDimension   = modelDimension
        self.hiddenDimension  = hiddenDimension
        self.layerCount       = layerCount
        self.headCount        = headCount
        self.headDimension    = modelDimension / headCount
    }

    var embeddingParameters: Int {
        vocabularySize * modelDimension
    }

    var attentionParametersPerLayer: Int {
        4 * modelDimension * modelDimension
    }

    var feedForwardParametersPerLayer: Int {
        3 * modelDimension * hiddenDimension
    }

    var normalizationParametersPerLayer: Int {
        2 * modelDimension
    }

    var blockParameters: Int {
        layerCount * (
            attentionParametersPerLayer +
            feedForwardParametersPerLayer +
            normalizationParametersPerLayer
        )
    }

    var approximateParameterCount: Int {
        embeddingParameters + blockParameters + modelDimension
    }
}
