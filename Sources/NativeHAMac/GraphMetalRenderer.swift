import MetalKit
import SwiftUI
import NativeHACore

struct MetalGraphView: NSViewRepresentable {
    let rendered: GraphRenderResult

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = graphMetalClearColor
        mtkView.sampleCount = GraphMetalRenderer.sampleCount
        mtkView.delegate = context.coordinator

        if let device = mtkView.device {
            context.coordinator.setup(device: device)
        }
        return mtkView
    }

    func updateNSView(_ mtkView: MTKView, context: Context) {
        context.coordinator.update(rendered: rendered)
        mtkView.setNeedsDisplay(mtkView.bounds)
    }

    func makeCoordinator() -> GraphMetalRenderer {
        GraphMetalRenderer()
    }
}

private let graphMetalClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

private struct GraphMetalVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct GraphMetalPreparedBatch {
    let primitiveType: MTLPrimitiveType
    let buffer: MTLBuffer
    let vertexCount: Int
}

private struct GraphMetalPreparedFrame {
    let batches: [GraphMetalPreparedBatch]
    let vertexCount: Int
}

struct GraphMetalRenderCompletion {
    let vertexCount: Int
    let geometryNanoseconds: UInt64
    let commandNanoseconds: UInt64
}

class GraphMetalRenderer: NSObject, MTKViewDelegate {
    static let sampleCount = 4

    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var rendered: GraphRenderResult?
    private var device: MTLDevice?

    func setup(device: MTLDevice) {
        self.device = device
        commandQueue = device.makeCommandQueue()

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float2 position [[attribute(0)]];
            float4 color [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = float4(in.position, 0.0, 1.0);
            out.color = in.color;
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let fragmentFunction = library.makeFunction(name: "fragment_main") else {
                return
            }

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float4
            vertexDescriptor.attributes[1].offset = 16
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<GraphMetalVertex>.stride
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.rasterSampleCount = Self.sampleCount
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            AppLog("Failed to compile Metal shaders: \(error)", severity: .error, category: .rendering)
        }
    }

    func update(rendered: GraphRenderResult) {
        self.rendered = rendered
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let rendered = rendered,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              ),
              let prepared = makePreparedFrame(rendered: rendered, size: view.bounds.size)
        else {
            return
        }

        encode(prepared, with: encoder)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Offscreen production renderer completion used by performance benchmarks.
    /// It waits for the requested Metal command buffer, but not compositor
    /// presentation or display scanout.
    func renderOffscreenForBenchmark(
        rendered: GraphRenderResult
    ) -> GraphMetalRenderCompletion? {
        guard let device = device,
              let commandQueue = commandQueue,
              pipelineState != nil else {
            return nil
        }

        let geometryStart = DispatchTime.now().uptimeNanoseconds
        guard let prepared = makePreparedFrame(rendered: rendered, size: rendered.size),
              prepared.vertexCount > 0 else {
            return nil
        }
        let geometryNanoseconds = DispatchTime.now().uptimeNanoseconds - geometryStart

        let width = max(Int(rendered.size.width * rendered.scale), 1)
        let height = max(Int(rendered.size.height * rendered.scale), 1)
        let multisampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        multisampleDescriptor.textureType = .type2DMultisample
        multisampleDescriptor.sampleCount = Self.sampleCount
        multisampleDescriptor.storageMode = .private
        multisampleDescriptor.usage = [.renderTarget]

        let resolveDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        resolveDescriptor.storageMode = .shared
        resolveDescriptor.usage = [.renderTarget, .shaderRead]

        guard let multisampleTexture = device.makeTexture(descriptor: multisampleDescriptor),
              let resolveTexture = device.makeTexture(descriptor: resolveDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = multisampleTexture
        renderPass.colorAttachments[0].resolveTexture = resolveTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .multisampleResolve
        renderPass.colorAttachments[0].clearColor = graphMetalClearColor

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return nil
        }
        let commandStart = DispatchTime.now().uptimeNanoseconds
        encode(prepared, with: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let commandNanoseconds = DispatchTime.now().uptimeNanoseconds - commandStart

        guard commandBuffer.status == .completed, commandBuffer.error == nil else {
            return nil
        }
        return GraphMetalRenderCompletion(
            vertexCount: prepared.vertexCount,
            geometryNanoseconds: geometryNanoseconds,
            commandNanoseconds: commandNanoseconds
        )
    }

    private func encode(
        _ prepared: GraphMetalPreparedFrame,
        with encoder: MTLRenderCommandEncoder
    ) {
        guard let pipelineState = pipelineState else { return }
        encoder.setRenderPipelineState(pipelineState)
        for batch in prepared.batches {
            encoder.setVertexBuffer(batch.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: batch.primitiveType,
                vertexStart: 0,
                vertexCount: batch.vertexCount
            )
        }
    }

    private func makePreparedFrame(
        rendered: GraphRenderResult,
        size: CGSize
    ) -> GraphMetalPreparedFrame? {
        guard size.width > 0, size.height > 0, let device = device else {
            return nil
        }

        let batches: [GraphMetalPreparedBatch]
        if rendered.unit.lowercased() == "state" {
            batches = timelineBatches(rendered: rendered, size: size, device: device)
        } else {
            batches = numericBatches(rendered: rendered, size: size, device: device)
        }
        return GraphMetalPreparedFrame(
            batches: batches,
            vertexCount: batches.reduce(0) { $0 + $1.vertexCount }
        )
    }

    private func numericBatches(
        rendered: GraphRenderResult,
        size: CGSize,
        device: MTLDevice
    ) -> [GraphMetalPreparedBatch] {
        var batches: [GraphMetalPreparedBatch] = []
        batches.reserveCapacity(rendered.series.count)

        for item in rendered.series {
            let color = SIMD4<Float>(
                Float(item.color.red),
                Float(item.color.green),
                Float(item.color.blue),
                Float(item.color.alpha)
            )
            let vertices = item.points.map { point in
                vertex(
                    x: rendered.x(for: point.t),
                    y: rendered.y(for: point.y),
                    color: color,
                    size: size
                )
            }
            guard vertices.count >= 2,
                  let buffer = device.makeBuffer(
                    bytes: vertices,
                    length: vertices.count * MemoryLayout<GraphMetalVertex>.stride,
                    options: .storageModeShared
                  ) else {
                continue
            }
            batches.append(GraphMetalPreparedBatch(
                primitiveType: .lineStrip,
                buffer: buffer,
                vertexCount: vertices.count
            ))
        }
        return batches
    }

    private func timelineBatches(
        rendered: GraphRenderResult,
        size: CGSize,
        device: MTLDevice
    ) -> [GraphMetalPreparedBatch] {
        let maxRowHeight: CGFloat = 24
        let rowHeight = min(
            rendered.plotRect.height / CGFloat(max(rendered.series.count, 1)),
            maxRowHeight
        )
        let totalHeight = rowHeight * CGFloat(rendered.series.count)
        let startY = rendered.plotRect.minY + (rendered.plotRect.height - totalHeight) / 2
        var vertices: [GraphMetalVertex] = []

        for (index, item) in rendered.series.enumerated() {
            let yOffset = startY + CGFloat(index) * rowHeight
            for segment in item.timelineSegments {
                let startX = max(rendered.plotRect.minX, rendered.x(for: segment.clippedStart))
                let endX = min(rendered.plotRect.maxX, rendered.x(for: segment.clippedEnd))
                guard endX > startX else { continue }
                let graphColor = GraphColor(
                    hex: HAHistoryTimelineColorResolver.color(
                        for: segment.state,
                        entityID: item.entityID
                    ).hex
                ) ?? GraphColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
                let color = SIMD4<Float>(
                    Float(graphColor.red),
                    Float(graphColor.green),
                    Float(graphColor.blue),
                    Float(graphColor.alpha)
                )
                let top = yOffset + 2
                let bottom = top + max(rowHeight - 4, 1)
                let topLeft = vertex(x: startX, y: top, color: color, size: size)
                let bottomLeft = vertex(x: startX, y: bottom, color: color, size: size)
                let topRight = vertex(x: endX, y: top, color: color, size: size)
                let bottomRight = vertex(x: endX, y: bottom, color: color, size: size)
                vertices.append(contentsOf: [
                    topLeft, bottomLeft, topRight,
                    bottomRight, bottomLeft, topRight,
                ])
            }
        }

        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<GraphMetalVertex>.stride,
                options: .storageModeShared
              ) else {
            return []
        }
        return [GraphMetalPreparedBatch(
            primitiveType: .triangle,
            buffer: buffer,
            vertexCount: vertices.count
        )]
    }

    private func vertex(
        x: CGFloat,
        y: CGFloat,
        color: SIMD4<Float>,
        size: CGSize
    ) -> GraphMetalVertex {
        GraphMetalVertex(
            position: SIMD2<Float>(
                (Float(x) / Float(size.width)) * 2 - 1,
                1 - (Float(y) / Float(size.height)) * 2
            ),
            color: color
        )
    }
}
