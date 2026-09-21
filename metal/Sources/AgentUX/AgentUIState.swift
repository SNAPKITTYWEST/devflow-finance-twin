import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#else
public struct CGPoint: Sendable { public var x: Double; public var y: Double; public static let zero = CGPoint(x: 0, y: 0) }
public struct CGRect: Sendable { public var x, y, width, height: Double }
#endif

@Observable
public final class AgentUIState: @unchecked Sendable {
    public var windowTitle: String = "Initializing BEAM…"
    public var activeAgentsCount: Int = 0
    public var canvasOpacity: Double = 0
    public var avatarTarget: CGPoint = .zero
    public var glass: Double = 0.35
    public var frame: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6)
    public var lastSeq: UInt16 = 0
    public var lastOp: UInt8 = 0

    public init() {}

    @MainActor
    public func apply(_ frame: DylanFrame) {
        lastSeq = frame.seq
        lastOp = frame.op
        switch DylanOp(rawValue: frame.op) {
        case .hello, .setTitle:
            if let title = String(data: frame.payload, encoding: .utf8) {
                windowTitle = title
            }
        case .setAgentCount where frame.payload.count >= 2:
            activeAgentsCount = Int(frame.payload.withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) })
        case .updateAvatarPos:
            if let (x, y) = DylanPayload.point(frame.payload) {
                avatarTarget = CGPoint(x: Double(x), y: Double(y))
            }
        case .drawWindowFrame:
            if let (x, y, w, h) = DylanPayload.rect(frame.payload) {
                self.frame = CGRect(x: Double(x), y: Double(y), width: Double(w), height: Double(h))
            }
        case .synthesizeGlass where frame.payload.count >= 4:
            let v = frame.payload.withUnsafeBytes { $0.load(as: Float.self) }
            glass = Double(v)
        default:
            break
        }
        canvasOpacity = min(1, canvasOpacity + 0.08)
    }
}
