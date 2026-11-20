//
//  DialogueCompletionAuroraView.swift
//  shizen
//
//  The animated gold glow behind the completion screens' headers, drawn with
//  Metal (DialogueCompletionAurora.metal) and softened with an MPS blur. With
//  Reduce Motion on it draws a still gold gradient once instead.
//

import MetalKit
import MetalPerformanceShaders
import UIKit

struct DialogueAuroraConfiguration: Equatable {
    var intensity: Float
    var bands: Float
    var speed: Float
    var contrast: Float
    var opacity: Float
    /// Points.
    var blur: CGFloat
    var fadeLocation: Float
    var height: CGFloat

    static let production = DialogueAuroraConfiguration(
        intensity: 1,
        bands: 4,
        speed: 1.3,
        contrast: 2.2,
        opacity: 0.62,
        blur: 8,
        fadeLocation: 0.62,
        height: 270
    )
}

/// Matches `AuroraUniforms` in DialogueCompletionAurora.metal.
private struct AuroraUniforms {
    var size: SIMD2<Float>
    var time: Float
    var intensity: Float
    var bands: Float
    var speed: Float
    var contrast: Float
    var opacity: Float
    var fadeLocation: Float
    var isStatic: UInt32
}

final class DialogueCompletionAuroraView: UIView {
    private let configuration: DialogueAuroraConfiguration
    private let renderer: Renderer?
    private let metalView: MTKView?

    init(configuration: DialogueAuroraConfiguration = .production) {
        self.configuration = configuration
        let device = MTLCreateSystemDefaultDevice()
        renderer = device.flatMap { Renderer(device: $0, configuration: configuration) }
        metalView = renderer.map { MTKView(frame: .zero, device: $0.device) }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear

        guard let metalView, let renderer else { return }
        metalView.delegate = renderer
        metalView.colorPixelFormat = .bgra8Unorm
        // MPS writes the blur straight into the drawable.
        metalView.framebufferOnly = false
        metalView.isOpaque = false
        metalView.backgroundColor = .clear
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // The glow is blurred anyway; 1x looks the same and costs a fraction.
        metalView.contentScaleFactor = 1
        metalView.preferredFramesPerSecond = 60
        metalView.frame = bounds
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(metalView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePlayback),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        updatePlayback()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    /// Animates while on screen; with Reduce Motion, draws the still gradient on demand only.
    @objc private func updatePlayback() {
        guard let metalView, let renderer else { return }
        let isStatic = UIAccessibility.isReduceMotionEnabled
        renderer.isStatic = isStatic
        metalView.enableSetNeedsDisplay = isStatic
        metalView.isPaused = isStatic || window == nil
        if isStatic { metalView.setNeedsDisplay() }
    }

    // MARK: - Renderer

    private final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let queue: MTLCommandQueue
        private let pipeline: MTLRenderPipelineState
        private let blur: MPSImageGaussianBlur
        private let configuration: DialogueAuroraConfiguration
        /// The unblurred glow, at drawable size.
        private var glowTexture: MTLTexture?
        var isStatic = false

        init?(device: MTLDevice, configuration: DialogueAuroraConfiguration) {
            guard let queue = device.makeCommandQueue(),
                  let library = device.makeDefaultLibrary(),
                  let vertex = library.makeFunction(name: "aurora_vertex"),
                  let fragment = library.makeFunction(name: "aurora_fragment") else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            self.device = device
            self.queue = queue
            self.pipeline = pipeline
            self.configuration = configuration
            // Drawn at 1x, so points are pixels.
            blur = MPSImageGaussianBlur(device: device, sigma: Float(configuration.blur))
            blur.edgeMode = .zero
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            glowTexture = nil
        }

        func draw(in view: MTKView) {
            let size = view.drawableSize
            guard size.width > 0, size.height > 0,
                  let drawable = view.currentDrawable,
                  let glow = glowTexture(width: Int(size.width), height: Int(size.height)),
                  let commands = queue.makeCommandBuffer() else { return }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = glow
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms = AuroraUniforms(
                size: SIMD2(Float(view.bounds.width), Float(view.bounds.height)),
                time: Float(Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)),
                intensity: configuration.intensity,
                bands: configuration.bands,
                speed: configuration.speed,
                contrast: configuration.contrast,
                opacity: configuration.opacity,
                fadeLocation: configuration.fadeLocation,
                isStatic: isStatic ? 1 : 0
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AuroraUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            blur.encode(commandBuffer: commands, sourceTexture: glow, destinationTexture: drawable.texture)
            commands.present(drawable)
            commands.commit()
        }

        private func glowTexture(width: Int, height: Int) -> MTLTexture? {
            if let glowTexture, glowTexture.width == width, glowTexture.height == height {
                return glowTexture
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            glowTexture = device.makeTexture(descriptor: descriptor)
            return glowTexture
        }
    }
}
