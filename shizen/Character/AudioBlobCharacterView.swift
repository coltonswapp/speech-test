//
//  AudioBlobCharacterView.swift
//  shizen
//
//  Glowing icosahedron wireframe blob — Perlin displacement driven by audio level.
//

import MetalKit
import simd
import UIKit

final class AudioBlobCharacterView: UIView {

    private let metalView = MTKView()
    private var renderer: AudioBlobRenderer?

    private var targetLevel: Float = 0
    private var displayedLevel: Float = 0
    private var animationTime: Float = 0
    private var displayLink: CADisplayLink?
    private(set) var isSpeaking = false

    var noiseScale: Float = 3.2 {
        didSet { pushUniforms() }
    }

    var displacementScale: Float = 1.15 {
        didSet { pushUniforms() }
    }

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
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let blobRenderer = AudioBlobRenderer(device: device) {
            renderer = blobRenderer
            metalView.delegate = blobRenderer
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
        let smoothing: Float = isSpeaking ? 0.32 : 0.1
        let delta = targetLevel - displayedLevel
        if abs(delta) > 0.0005 {
            displayedLevel += delta * smoothing
        }
        pushUniforms()
    }

    private func pushUniforms() {
        let size = metalView.drawableSize
        let aspect: Float = size.height > 0 ? Float(size.width / size.height) : 1
        renderer?.updateFrame(
            aspect: aspect,
            time: animationTime,
            frequency: displayedLevel * 100,
            noiseScale: noiseScale,
            displacementScale: displacementScale,
            speaking: isSpeaking
        )
    }
}

// MARK: - Icosahedron mesh

private struct BlobGPUVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var barycentric: SIMD3<Float>
}

private enum IcosahedronMesh {
    static func make(subdivisions: Int, radius: Float = 1) -> ([BlobGPUVertex], [UInt16]) {
        let phi = Float(1.618_033_988_7)
        var vertices: [SIMD3<Float>] = [
            SIMD3(-1, phi, 0), SIMD3(1, phi, 0), SIMD3(-1, -phi, 0), SIMD3(1, -phi, 0),
            SIMD3(0, -1, phi), SIMD3(0, 1, phi), SIMD3(0, -1, -phi), SIMD3(0, 1, -phi),
            SIMD3(phi, 0, -1), SIMD3(phi, 0, 1), SIMD3(-phi, 0, -1), SIMD3(-phi, 0, 1),
        ].map { simd_normalize($0) * radius }

        var faces: [UInt32] = [
            0, 11, 5,   0, 5, 1,    0, 1, 7,    0, 7, 10,   0, 10, 11,
            1, 5, 9,    5, 11, 4,   11, 10, 2,  10, 7, 6,    7, 1, 8,
            3, 9, 4,    3, 4, 2,    3, 2, 6,    3, 6, 8,    3, 8, 9,
            4, 9, 5,    2, 4, 11,   6, 2, 10,   8, 6, 7,    9, 8, 1,
        ]

        var midpointCache: [UInt64: UInt32] = [:]

        func midpoint(_ a: UInt32, _ b: UInt32) -> UInt32 {
            let key = a < b ? (UInt64(a) << 32 | UInt64(b)) : (UInt64(b) << 32 | UInt64(a))
            if let cached = midpointCache[key] { return cached }
            let mid = simd_normalize((vertices[Int(a)] + vertices[Int(b)]) * 0.5) * radius
            let index = UInt32(vertices.count)
            vertices.append(mid)
            midpointCache[key] = index
            return index
        }

        for _ in 0..<subdivisions {
            var nextFaces: [UInt32] = []
            nextFaces.reserveCapacity(faces.count * 4)
            var f = 0
            while f < faces.count {
                let a = faces[f], b = faces[f + 1], c = faces[f + 2]
                let ab = midpoint(a, b)
                let bc = midpoint(b, c)
                let ca = midpoint(c, a)
                nextFaces += [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]
                f += 3
            }
            faces = nextFaces
        }

        var gpuVertices: [BlobGPUVertex] = []
        gpuVertices.reserveCapacity(faces.count)
        for f in stride(from: 0, to: faces.count, by: 3) {
            let indices = (faces[f], faces[f + 1], faces[f + 2])
            let corners: [(UInt32, SIMD3<Float>)] = [
                (indices.0, SIMD3(1, 0, 0)),
                (indices.1, SIMD3(0, 1, 0)),
                (indices.2, SIMD3(0, 0, 1)),
            ]
            for (index, bary) in corners {
                let pos = vertices[Int(index)]
                gpuVertices.append(BlobGPUVertex(position: pos, normal: simd_normalize(pos), barycentric: bary))
            }
        }

        let drawIndices = (0..<UInt16(gpuVertices.count)).map { $0 }
        return (gpuVertices, drawIndices)
    }
}

// MARK: - Metal renderer

private struct AudioBlobUniforms {
    var modelViewProjection: simd_float4x4
    var modelMatrix: simd_float4x4
    var time: Float
    var frequency: Float
    var noiseScale: Float
    var displacementScale: Float
    var color: SIMD4<Float>
    var speaking: Float
}

private final class AudioBlobRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer

    private var uniforms = AudioBlobUniforms(
        modelViewProjection: matrix_identity_float4x4,
        modelMatrix: matrix_identity_float4x4,
        time: 0,
        frequency: 0,
        noiseScale: 3.2,
        displacementScale: 1.15,
        color: SIMD4(1, 0.82, 0.22, 1),
        speaking: 0
    )

    private let indexCount: Int

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        commandQueue = queue

        let (vertices, indices) = IcosahedronMesh.make(subdivisions: 3, radius: 1)
        indexCount = indices.count
        guard let vBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<BlobGPUVertex>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            return nil
        }
        vertexBuffer = vBuffer

        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "audioBlobVertex"),
              let fragmentFn = library.makeFunction(name: "audioBlobFragment")
        else {
            return nil
        }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<BlobGPUVertex>.stride

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
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

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.isDepthWriteEnabled = true
        depthDescriptor.depthCompareFunction = .less
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        depthState = depth

        super.init()
        _ = indices
    }

    func updateFrame(aspect: Float, time: Float, frequency: Float, noiseScale: Float, displacementScale: Float, speaking: Bool) {
        let rotation = simd_float4x4(rotationY: time * 0.38) * simd_float4x4(rotationX: -0.42)
        let model = rotation
        let view = simd_float4x4(translation: SIMD3(0, 0, -3.15))
        let projection = simd_float4x4(perspectiveFovY: 45 * .pi / 180, aspect: aspect, near: 0.1, far: 100)
        uniforms.modelMatrix = model
        uniforms.modelViewProjection = projection * view * model
        uniforms.time = time
        uniforms.frequency = frequency
        uniforms.noiseScale = noiseScale
        uniforms.displacementScale = displacementScale
        uniforms.speaking = speaking ? 1 : 0
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else {
            return
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment?.loadAction = .clear
        pass.depthAttachment?.clearDepth = 1

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var u = uniforms
        encoder.setVertexBytes(&u, length: MemoryLayout<AudioBlobUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&u, length: MemoryLayout<AudioBlobUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: indexCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Matrix helpers

private extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t.x, t.y, t.z, 1)
    }

    init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = simd_float4x4(
            SIMD4(c, 0, s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(-s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, -s, 0),
            SIMD4(0, s, c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    init(perspectiveFovY fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        self = simd_float4x4(
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        )
    }
}
