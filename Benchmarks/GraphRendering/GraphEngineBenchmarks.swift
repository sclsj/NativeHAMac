import XCTest
import CoreGraphics
import MetalKit
import SwiftUI
@testable import NativeHACore
@testable import NativeHAMac

final class GraphEngineBenchmarks: XCTestCase {

    struct BenchmarkResults {
        var coreGraphicsTimes: [UInt64] = []
        var metalTimes: [UInt64] = []
        var canvasTimes: [UInt64] = []
    }

    struct MockSeries: Codable {
        let entityID: String
        let points: [HAHistoryPoint]
        let contentRevision: UInt64?
    }

    func testEngineComparison() throws {
        let jsonURL = URL(fileURLWithPath: "/Users/jin/Documents/Computer/NativeHA/sps30_1day.json")
        let data = try Data(contentsOf: jsonURL)
        let mockData = try JSONDecoder().decode([MockSeries].self, from: data)
        let history = mockData.map { HAHistorySeries(entityID: $0.entityID, points: $0.points, contentRevision: $0.contentRevision) }
        
        let inputs = history.enumerated().map { index, series in
            GraphRenderSeriesInput(
                entityID: series.entityID,
                name: series.entityID,
                unit: "μg/m³",
                color: GraphColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                history: series
            )
        }
        
        let size = CGSize(width: 500, height: 200)
        let scale: CGFloat = 2.0
        
        var results = BenchmarkResults()
        
        // Setup metal view if possible
        let mtkView = MTKView(frame: NSRect(origin: .zero, size: size))
        let device = MTLCreateSystemDefaultDevice()
        mtkView.device = device
        let renderer = GraphMetalRenderer()
        if let dev = device {
            renderer.setup(device: dev)
        }

        let iterations = 20
        
        for i in 0..<iterations {
            let panFraction = Double(i) / Double(iterations - 1)
            
            // CoreGraphics
            var cgTime: UInt64 = 0
            AppConfig.graphRenderEngine = .coreGraphics
            _ = GraphBitmapRenderer.render(
                inputs: inputs,
                unit: "μg/m³",
                size: size,
                scale: scale,
                zoomScale: 4.0,
                panFraction: panFraction
            ) { metrics in
                cgTime = metrics.pathConstructionNanoseconds + metrics.pathStrokeNanoseconds
            }
            if cgTime > 0 {
                results.coreGraphicsTimes.append(cgTime)
            }
            
            // Prepare data for others
            if let prepared = GraphBitmapRenderer.prepareViewportData(
                inputs: inputs,
                unit: "μg/m³",
                size: size,
                scale: scale,
                zoomScale: 4.0,
                panFraction: panFraction
            ) {
                let rendered = prepared.result
                
                // Canvas path building simulation
                let canvasStart = DispatchTime.now().uptimeNanoseconds
                for item in rendered.series {
                    var path = Path()
                    for (index, point) in item.points.enumerated() {
                        let mapped = CGPoint(
                            x: rendered.x(for: point.t),
                            y: rendered.y(for: point.y)
                        )
                        if index == 0 {
                            path.move(to: mapped)
                        } else {
                            path.addLine(to: mapped)
                        }
                    }
                }
                let canvasEnd = DispatchTime.now().uptimeNanoseconds
                results.canvasTimes.append(canvasEnd - canvasStart)
                
                // Metal vertex construction simulation (what would run on CPU before GPU)
                if let _ = device {
                    let metalStart = DispatchTime.now().uptimeNanoseconds
                    
                    let viewWidth = Float(size.width)
                    let viewHeight = Float(size.height)
                    struct Vertex {
                        var position: SIMD2<Float>
                        var color: SIMD4<Float>
                    }
                    var totalVerticesCount = 0
                    
                    for item in rendered.series {
                        var lineVertices = [Vertex]()
                        lineVertices.reserveCapacity(item.points.count)
                        let color = SIMD4<Float>(Float(item.color.red), Float(item.color.green), Float(item.color.blue), Float(item.color.alpha))
                        
                        for point in item.points {
                            let x = rendered.x(for: point.t)
                            let y = rendered.y(for: point.y)
                            
                            let ndcX = (Float(x) / viewWidth) * 2.0 - 1.0
                            let ndcY = 1.0 - (Float(y) / viewHeight) * 2.0
                            
                            lineVertices.append(Vertex(position: SIMD2<Float>(ndcX, ndcY), color: color))
                        }
                        totalVerticesCount += lineVertices.count
                        
                        if lineVertices.count >= 2 {
                            // Mocking the buffer creation
                            _ = device?.makeBuffer(bytes: lineVertices, length: lineVertices.count * MemoryLayout<Vertex>.stride, options: .storageModeShared)
                        }
                    }
                    let metalEnd = DispatchTime.now().uptimeNanoseconds
                    results.metalTimes.append(metalEnd - metalStart)
                }
            }
        }
        
        let cgMedian = (results.coreGraphicsTimes.sorted()[results.coreGraphicsTimes.count / 2])
        let cvMedian = (results.canvasTimes.sorted()[results.canvasTimes.count / 2])
        let mtMedian = (results.metalTimes.sorted()[results.metalTimes.count / 2])
        
        print("--- PERFORMANCE REPORT ---")
        print("Median CoreGraphics (Construct+Stroke): \(Double(cgMedian) / 1_000_000.0) ms")
        print("Median Canvas (Path Construct): \(Double(cvMedian) / 1_000_000.0) ms")
        print("Median Metal (Vertex Construct+Buffer): \(Double(mtMedian) / 1_000_000.0) ms")
    }
}
