import XCTest
import Metal
@testable import MetalTransformer

final class MetalTransformerTests: XCTestCase {
    func testDeviceAndPipelinesLoad() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let engine = try MetalTransformer()
        XCTAssertEqual(engine.dimensions.headDim, 128)
    }
}
