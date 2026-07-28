import XCTest
@testable import NativeHACore
@testable import NativeHAMac
import Foundation

final class PrepareFullBenchmarks: XCTestCase {
    func testPrepareFull() throws {
        let url = URL(fileURLWithPath: "/Users/jin/Documents/Computer/NativeHA/sps30_1day.json")
        let data = try Data(contentsOf: url)
        
        let decodedArray = try JSONDecoder().decode([HAHistorySeries].self, from: data)
        let first = decodedArray[0]
        
        let input = GraphRenderSeriesInput(
            entityID: first.entityID,
            name: "PM2.5",
            unit: "µg/m³",
            color: GraphColor(red: 0, green: 0, blue: 1, alpha: 1),
            history: first
        )

        GraphBitmapRenderer.resetPreparedSeriesCache()
        _ = GraphBitmapRenderer.preparedSeriesForTesting(input, displayUnit: "µg/m³")
        
        let options = XCTMeasureOptions.default
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            GraphBitmapRenderer.resetPreparedSeriesCache()
            _ = GraphBitmapRenderer.preparedSeriesForTesting(input, displayUnit: "µg/m³")
        }
    }
}
