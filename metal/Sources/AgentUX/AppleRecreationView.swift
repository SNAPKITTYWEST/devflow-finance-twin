#if canImport(SwiftUI)
import SwiftUI
import MetalKit

public struct AppleRecreationView: View {
    @State private var state = AgentUIState()
    @State private var streamTask: Task<Void, Never>?

    private let client: DylanClient

    public init(client: DylanClient) {
        self.client = client
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                MetalAvatarCanvas(state: state)
                    .frame(minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.55), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .opacity(state.canvasOpacity == 0 ? 0.4 : state.canvasOpacity)
            }
            .padding(22)
        }
        .frame(minWidth: 680, minHeight: 460)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: state.avatarTarget.x)
        .task { await pump() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.cyan)
            Text(state.windowTitle)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
            Spacer()
            Text("BEAM nodes \(state.activeAgentsCount)")
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.10)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.28)))
    }

    @MainActor
    private func pump() async {
        for await frame in await client.frames() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                state.apply(frame)
            }
        }
    }
}

#if canImport(AppKit)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

final class AvatarRenderer: NSObject, MTKViewDelegate {
    let state: AgentUIState
    let device: MTLDevice
    let queue: MTLCommandQueue
    var pipeline: MTLComputePipelineState?
    var renderPipe: MTLRenderPipelineState?
    var particles: MTLBuffer?
    let count = 65_536

    init?(state: AgentUIState) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.state = state
        self.device = device
        self.queue = queue
        super.init()
        particles = device.makeBuffer(length: count * 48, options: .storageModeShared)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let buf = queue.makeCommandBuffer(),
              let drawable = view.currentDrawable else { return }
        buf.present(drawable)
        buf.commit()
    }
}

struct MetalAvatarCanvas: NSViewRepresentable {
    let state: AgentUIState

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 120
        if let renderer = AvatarRenderer(state: state) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var renderer: AvatarRenderer? }
}
#endif
#endif
