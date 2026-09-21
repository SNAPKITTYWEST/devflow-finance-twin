import Foundation

public enum DylanOp: UInt8, Sendable {
    case hello = 0x01
    case updateAvatarPos = 0x0A
    case setTitle = 0x0B
    case setAgentCount = 0x0C
    case drawWindowFrame = 0x0D
    case synthesizeGlass = 0x0E
    case congestion = 0x0F
    case spawnAgent = 0x10
    case retireAgent = 0x11
}

public struct DylanFrame: Sendable, Equatable {
    public var agentID: Data
    public var op: UInt8
    public var flags: UInt8
    public var seq: UInt16
    public var payload: Data

    public init(agentID: Data, op: UInt8, flags: UInt8 = 0, seq: UInt16 = 0, payload: Data) {
        self.agentID = agentID
        self.op = op
        self.flags = flags
        self.seq = seq
        self.payload = payload
    }

    public static let magic = Data([0x44, 0x59, 0x4C, 0x41])
    public static let headerSize = 26
    public static let crcSize = 4

    public func encode(crc: (Data) -> UInt32) -> Data {
        var body = Data(capacity: Self.headerSize + payload.count + Self.crcSize)
        body.append(Self.magic)
        body.append(agentID)
        body.append(op)
        body.append(flags)
        body.append(contentsOf: withUnsafeBytes(of: seq.bigEndian, Array.init))
        body.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian, Array.init))
        body.append(payload)
        var digest = crc(body).bigEndian
        withUnsafeBytes(of: &digest) { body.append(contentsOf: $0) }
        return body
    }

    public static func decode(_ data: Data, crc: (Data) -> UInt32) -> DylanFrame? {
        guard data.count >= headerSize + crcSize else { return nil }
        guard data.prefix(4) == magic else { return nil }
        let lenOff = 24
        let len = data.subdata(in: lenOff..<(lenOff + 2)).withUnsafeBytes {
            UInt16(bigEndian: $0.load(as: UInt16.self))
        }
        let total = headerSize + Int(len) + crcSize
        guard data.count >= total else { return nil }
        let body = data.subdata(in: 0..<(headerSize + Int(len)))
        let got = data.subdata(in: (headerSize + Int(len))..<total).withUnsafeBytes {
            UInt32(bigEndian: $0.load(as: UInt32.self))
        }
        guard crc(body) == got else { return nil }
        return DylanFrame(
            agentID: data.subdata(in: 4..<20),
            op: data[20],
            flags: data[21],
            seq: data.subdata(in: 22..<24).withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) },
            payload: data.subdata(in: headerSize..<(headerSize + Int(len)))
        )
    }
}

public enum DylanPayload {
    public static func point(_ data: Data) -> (Float, Float)? {
        guard data.count >= 8 else { return nil }
        return data.withUnsafeBytes { raw in
            let x = raw.load(fromByteOffset: 0, as: Float.self)
            let y = raw.load(fromByteOffset: 4, as: Float.self)
            return (x, y)
        }
    }

    public static func rect(_ data: Data) -> (Float, Float, Float, Float)? {
        guard data.count >= 16 else { return nil }
        return data.withUnsafeBytes { raw in
            (
                raw.load(fromByteOffset: 0, as: Float.self),
                raw.load(fromByteOffset: 4, as: Float.self),
                raw.load(fromByteOffset: 8, as: Float.self),
                raw.load(fromByteOffset: 12, as: Float.self)
            )
        }
    }
}
