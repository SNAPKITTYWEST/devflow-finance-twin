import Foundation

public actor DylanClient {
    public typealias CRC = @Sendable (Data) -> UInt32

    private let host: String
    private let port: Int
    private let crc: CRC
    private var sink: AsyncStream<DylanFrame>.Continuation?

    public init(host: String, port: Int, crc: @escaping CRC) {
        self.host = host
        self.port = port
        self.crc = crc
    }

    public func frames() -> AsyncStream<DylanFrame> {
        AsyncStream { continuation in
            continuation.onTermination = { _ in }
            Task { await self.install(continuation) }
        }
    }

    private func install(_ c: AsyncStream<DylanFrame>.Continuation) {
        sink = c
    }

    public func ingest(_ bytes: Data) {
        guard let frame = DylanFrame.decode(bytes, crc: crc) else { return }
        sink?.yield(frame)
    }

    public func congestion(_ level: UInt8) -> Data {
        let frame = DylanFrame(
            agentID: Data(repeating: 0, count: 16),
            op: DylanOp.congestion.rawValue,
            payload: Data([level])
        )
        return frame.encode(crc: crc)
    }
}
