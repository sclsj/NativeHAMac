import MetalKit
import SwiftUI
import NativeHACore

struct MetalGraphView: NSViewRepresentable {
    let rendered: GraphRenderResult
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.sampleCount = 4
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

class GraphMetalRenderer: NSObject, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var rendered: GraphRenderResult?
    private var device: MTLDevice?
    
    func setup(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
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
            
            vertexDescriptor.layouts[0].stride = 32
            vertexDescriptor.layouts[0].stepFunction = .perVertex
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.rasterSampleCount = 4
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to compile Metal shaders: \\(error)")
        }
    }
    
    func update(rendered: GraphRenderResult) {
        self.rendered = rendered
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let rendered = rendered else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        
        let viewWidth = Float(view.bounds.width)
        let viewHeight = Float(view.bounds.height)
        
        guard viewWidth > 0, viewHeight > 0, let device = self.device else {
            encoder.endEncoding()
            return
        }
        
        struct Vertex {
            var position: SIMD2<Float>
            var color: SIMD4<Float>
        }
        
        var vertices = [Vertex]()
        
        if rendered.unit.lowercased() == "state" {
            let maxRowHeight: CGFloat = 24
            let rowHeight = min(rendered.plotRect.height / CGFloat(max(rendered.series.count, 1)), maxRowHeight)
            let totalHeight = rowHeight * CGFloat(rendered.series.count)
            let startY = rendered.plotRect.minY + (rendered.plotRect.height - totalHeight) / 2
            
            for (index, item) in rendered.series.enumerated() {
                let yOffset = startY + CGFloat(index) * rowHeight
                for segment in item.timelineSegments {
                    let startX = max(
                        rendered.plotRect.minX,
                        rendered.x(for: segment.clippedStart)
                    )
                    let endX = min(
                        rendered.plotRect.maxX,
                        rendered.x(for: segment.clippedEnd)
                    )
                    let blockWidth = endX - startX
                    if blockWidth <= 0 { continue }
                    
                    let hex = HAHistoryTimelineColorResolver.color(for: segment.state, entityID: item.entityID).hex
                    let gc = GraphColor(hex: hex) ?? GraphColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
                    let color = SIMD4<Float>(Float(gc.red), Float(gc.green), Float(gc.blue), Float(gc.alpha))
                    
                    let yTop = Float(yOffset + 2)
                    let yBottom = Float(yOffset + 2 + max(rowHeight - 4, 1))
                    let xLeft = Float(startX)
                    let xRight = Float(endX)
                    
                    let ndcLeft = (xLeft / viewWidth) * 2.0 - 1.0
                    let ndcRight = (xRight / viewWidth) * 2.0 - 1.0
                    let ndcTop = 1.0 - (yTop / viewHeight) * 2.0
                    let ndcBottom = 1.0 - (yBottom / viewHeight) * 2.0
                    
                    let v1 = Vertex(position: SIMD2<Float>(ndcLeft, ndcTop), color: color)
                    let v2 = Vertex(position: SIMD2<Float>(ndcLeft, ndcBottom), color: color)
                    let v3 = Vertex(position: SIMD2<Float>(ndcRight, ndcTop), color: color)
                    let v4 = Vertex(position: SIMD2<Float>(ndcRight, ndcBottom), color: color)
                    let v5 = Vertex(position: SIMD2<Float>(ndcLeft, ndcBottom), color: color)
                    let v6 = Vertex(position: SIMD2<Float>(ndcRight, ndcTop), color: color)
                    
                    vertices.append(contentsOf: [v1, v2, v3, v4, v5, v6])
                }
            }
            if vertices.isEmpty {
                encoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            if let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: .storageModeShared) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
        } else {
            for item in rendered.series {
                var lineVertices = [Vertex]()
                let color = SIMD4<Float>(Float(item.color.red), Float(item.color.green), Float(item.color.blue), Float(item.color.alpha))
                
                for point in item.points {
                    let x = rendered.x(for: point.t)
                    let y = rendered.y(for: point.y)
                    
                    let ndcX = (Float(x) / viewWidth) * 2.0 - 1.0
                    let ndcY = 1.0 - (Float(y) / viewHeight) * 2.0
                    
                    lineVertices.append(Vertex(position: SIMD2<Float>(ndcX, ndcY), color: color))
                }
                
                if lineVertices.count >= 2 {
                    if let buffer = device.makeBuffer(bytes: lineVertices, length: lineVertices.count * MemoryLayout<Vertex>.stride, options: .storageModeShared) {
                        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                        encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: lineVertices.count)
                    }
                }
            }
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
