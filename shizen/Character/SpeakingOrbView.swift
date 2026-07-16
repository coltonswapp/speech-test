//
//  SpeakingOrbView.swift
//  shizen
//
//  Metal-rendered yellow crystal ball whose inner glow responds to audio.
//

import MetalKit
import UIKit

final class SpeakingOrbView: UIView {

    private let metalView = MTKView()
    private var renderer: SiriOrbMetalRenderer?

    private var targetLevel: Float = 0
    private var displayedLevel: Float = 0
    private var animationTime: Float = 0
    private var displayLink: CADisplayLink?
    private(set) var isSpeaking = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false

        guard let device = MTLCreateSystemDefaultDevice() else { return }

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.device = device
        metalView.isOpaque = false
        metalView.backgroundColor = .clear
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.layer.isOpaque = false
        addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let orbRenderer = SiriOrbMetalRenderer(device: device) {
            renderer = orbRenderer
            metalView.delegate = orbRenderer
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    /// Push a new RMS level in [0, 1].
    func setLevel(_ level: Float) {
        targetLevel = max(0, min(1, level))
        isSpeaking = targetLevel > 0.02
    }

    func reset() {
        targetLevel = 0
        displayedLevel = 0
        isSpeaking = false
        pushUniforms()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        animationTime += Float(link.duration > 0 ? link.duration : 1.0 / 60.0)

        let smoothing: Float = isSpeaking ? 0.32 : 0.08
        let delta = targetLevel - displayedLevel
        if abs(delta) > 0.0005 {
            displayedLevel += delta * smoothing
        }

        pushUniforms()
    }

    private func pushUniforms() {
        let size = metalView.drawableSize
        let aspect: Float
        if size.height > 0 {
            aspect = Float(size.width / size.height)
        } else {
            aspect = 1
        }

        renderer?.uniforms = SiriOrbUniforms(
            time: animationTime,
            level: targetLevel,
            displayedLevel: displayedLevel,
            aspect: aspect,
            resolutionX: Float(size.width),
            resolutionY: Float(size.height),
            speaking: isSpeaking ? 1 : 0
        )
    }
}

// MARK: - Metal renderer

struct SiriOrbUniforms {
    var time: Float
    var level: Float
    var displayedLevel: Float
    var aspect: Float
    var resolutionX: Float
    var resolutionY: Float
    var speaking: Float
}

private final class SiriOrbMetalRenderer: NSObject, MTKViewDelegate {

    var uniforms = SiriOrbUniforms(
        time: 0,
        level: 0,
        displayedLevel: 0,
        aspect: 1,
        resolutionX: 0,
        resolutionY: 0,
        speaking: 0
    )

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }

        commandQueue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "siriOrbVertex"),
              let fragment = library.makeFunction(name: "siriOrbFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<SiriOrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
