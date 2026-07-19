import CoreGraphics
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class GraphRenderingTests: XCTestCase {
    func testNumericBitmapHasExpectedGeometryAxisAndPixels() throws {
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [numericInput()],
            unit: "°C",
            size: CGSize(width: 320, height: 160),
            scale: 2,
            zoomScale: 1,
            panFraction: 1
        ))

        XCTAssertEqual(result.image.width, 640)
        XCTAssertEqual(result.image.height, 320)
        XCTAssertEqual(result.plotRect, CGRect(x: 42, y: 18, width: 266, height: 116))
        XCTAssertEqual(result.axis.ticks, [15, 20, 25, 30])
        XCTAssertEqual(result.xTicks.count, 5)
        XCTAssertEqual(result.visibleStart, baseTimestamp, accuracy: 0.001)
        XCTAssertEqual(result.visibleEnd, baseTimestamp + 3_600, accuracy: 0.001)

        let pixels = try RGBAPixels(image: result.image)
        XCTAssertGreaterThan(
            pixels.count { pixel in
                Int(pixel.blue) > Int(pixel.red) + 80 &&
                    Int(pixel.blue) > Int(pixel.green) + 45
            },
            300,
            "The rendered bitmap should contain a visible graph line."
        )
    }

    func testTimelineBitmapPreservesStateSegmentsAndHoverState() throws {
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [timelineInput()],
            unit: HAHistoryGraphClassifier.stateUnit,
            size: CGSize(width: 320, height: 96),
            scale: 2,
            zoomScale: 1,
            panFraction: 1
        ))

        let segments = try XCTUnwrap(result.series.first?.timelineSegments)
        XCTAssertEqual(segments.map(\.state), ["off", "on", "unknown", "unavailable"])
        XCTAssertEqual(segments.first?.clippedStart, baseTimestamp)
        XCTAssertEqual(segments.last?.clippedEnd, baseTimestamp + 3_600)

        let sampleX = result.x(for: baseTimestamp + 1_350)
        let sample = try XCTUnwrap(result.sample(atX: sampleX))
        XCTAssertEqual(sample.values.first?.point.display, "on")

        let pixels = try RGBAPixels(image: result.image)
        let dominantSegmentColors = pixels.mostCommon(limit: 5).dropFirst().filter { $0.1 > 5_000 }
        XCTAssertEqual(
            dominantSegmentColors.count,
            4,
            "Each state segment should contribute a distinct solid color block."
        )
    }

    func testZoomAndPanSelectTheExpectedTimeWindow() throws {
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [numericInput()],
            unit: "°C",
            size: CGSize(width: 320, height: 160),
            scale: 1,
            zoomScale: 2,
            panFraction: 0.25
        ))

        XCTAssertEqual(result.visibleStart, baseTimestamp + 450, accuracy: 0.001)
        XCTAssertEqual(result.visibleEnd, baseTimestamp + 2_250, accuracy: 0.001)
        XCTAssertTrue(result.series.flatMap(\.points).allSatisfy {
            $0.t >= result.visibleStart && $0.t <= result.visibleEnd
        })
    }

    func testAnchoredZoomKeepsThePointerTimeStationary() {
        let pan = anchoredPanFraction(
            oldZoom: 1,
            newZoom: 2,
            oldPanFraction: 1,
            anchorFraction: 0.75
        )

        XCTAssertEqual(pan, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(
            anchoredPanFraction(
                oldZoom: 4,
                newZoom: 1,
                oldPanFraction: 0.2,
                anchorFraction: 0.4
            ),
            1
        )
    }

    func testPanDeltaGetsFinerAtHigherZoom() {
        let twoX = panDelta(for: 90, zoomScale: 2)
        let fiveX = panDelta(for: 90, zoomScale: 5)

        XCTAssertEqual(twoX, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(fiveX, 0.025, accuracy: 0.000_001)
    }

    func testHAReferenceHoverUsesThePreviousValue() throws {
        let input = GraphRenderSeriesInput(
            entityID: "sensor.reference_hover",
            name: "Reference hover",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.reference_hover",
                samples: [(0, "10"), (100, "20")]
            )
        )
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [input],
            unit: "°C",
            size: CGSize(width: 320, height: 160),
            scale: 1,
            zoomScale: 1,
            panFraction: 1
        ))
        let sample = try XCTUnwrap(result.sample(atX: result.x(for: baseTimestamp + 60)))

        XCTExpectFailure(
            "Known HA parity gap: hass-frontend uses the last sample at or before the hovered time; NativeHA currently chooses the nearest sample."
        )
        XCTAssertEqual(sample.values.first?.point.y, 10)
    }

    func testHAReferenceNumericHistoryUsesStepEndSegments() throws {
        let input = GraphRenderSeriesInput(
            entityID: "sensor.reference_steps",
            name: "Reference steps",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.reference_steps",
                samples: [(0, "10"), (100, "20")]
            )
        )
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [input],
            unit: "°C",
            size: CGSize(width: 254, height: 140),
            scale: 2,
            zoomScale: 1,
            panFraction: 1
        ))
        let pixels = try RGBAPixels(image: result.image)
        let expectedX = Int(result.x(for: baseTimestamp + 50) * result.scale)
        let expectedTopY = Int(result.y(for: 10) * result.scale)
        let hasHorizontalStep = pixels.containsBluePixel(
            nearX: expectedX,
            y: expectedTopY,
            radius: 4
        ) || pixels.containsBluePixel(
            nearX: expectedX,
            y: pixels.height - 1 - expectedTopY,
            radius: 4
        )

        XCTExpectFailure(
            "Known HA parity gap: hass-frontend renders state history with step: end; NativeHA currently connects numeric samples diagonally."
        )
        XCTAssertTrue(hasHorizontalStep)
    }

    func testSameShapeContentReplacementInvalidatesPreparedSeries() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let first = GraphRenderSeriesInput(
            entityID: "sensor.same_shape",
            name: "Same shape",
            unit: "°C",
            color: graphBlue,
            history: history(entityID: "sensor.same_shape", samples: [(0, "10"), (100, "20"), (200, "30")])
        )
        let replacement = GraphRenderSeriesInput(
            entityID: "sensor.same_shape",
            name: "Same shape",
            unit: "°C",
            color: graphBlue,
            history: history(entityID: "sensor.same_shape", samples: [(0, "10"), (100, "99"), (200, "30")])
        )

        let initial = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [first], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))
        let updated = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [replacement], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))
        XCTAssertEqual(initial.series.first?.points.map(\.y), [10, 20, 30])
        XCTAssertEqual(updated.series.first?.points.map(\.y), [10, 99, 30])
        XCTAssertNotEqual(first.history.contentRevision, replacement.history.contentRevision)
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 2,
                incrementalPreparationCount: 0,
                cacheHitCount: 0
            )
        )
    }

    func testEqualCountRollingTailUsesIncrementalPreparedSeriesPath() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let firstHistory = history(
            entityID: "sensor.rolling",
            samples: [(0, "10"), (100, "20"), (200, "30"), (300, "40")]
        )
        let first = GraphRenderSeriesInput(
            entityID: "sensor.rolling",
            name: "Rolling",
            unit: "°C",
            color: graphBlue,
            history: firstHistory
        )
        let rollingPoints = history(
            entityID: "sensor.rolling",
            samples: [(100, "20"), (200, "30"), (300, "40"), (400, "50")]
        ).points
        let rolling = GraphRenderSeriesInput(
            entityID: "sensor.rolling",
            name: "Rolling",
            unit: "°C",
            color: graphBlue,
            history: HAHistorySeries(
                entityID: "sensor.rolling",
                points: rollingPoints,
                contentRevision: firstHistory.contentRevision &+ 1,
                cacheLineage: HAHistorySeriesCacheLineage(
                    predecessorRevision: firstHistory.contentRevision,
                    oldStart: 1,
                    newStart: 0,
                    count: 3
                )
            )
        )

        _ = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [first], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))
        let updated = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [rolling], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))

        XCTAssertEqual(updated.series.first?.points.map(\.y), [20, 30, 40, 50])
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 1,
                incrementalPreparationCount: 1,
                cacheHitCount: 0
            )
        )
    }

    func testPreparedSeriesCacheScopesPreventOverlappingOwnersFromEvictingLineage() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let entityID = "sensor.shared_owner"
        let firstA = history(
            entityID: entityID,
            samples: [(0, "10"), (100, "20"), (200, "30"), (300, "40")]
        )
        let firstB = history(
            entityID: entityID,
            samples: [(1_000, "50"), (1_100, "60"), (1_200, "70"), (1_300, "80")]
        )
        let updatedA = HAHistorySeries(
            entityID: entityID,
            points: history(
                entityID: entityID,
                samples: [(100, "20"), (200, "30"), (300, "40"), (400, "50")]
            ).points,
            contentRevision: firstA.contentRevision &+ 1,
            cacheLineage: HAHistorySeriesCacheLineage(
                predecessorRevision: firstA.contentRevision,
                oldStart: 1,
                newStart: 0,
                count: 3
            )
        )
        let updatedB = HAHistorySeries(
            entityID: entityID,
            points: history(
                entityID: entityID,
                samples: [(1_100, "60"), (1_200, "70"), (1_300, "80"), (1_400, "90")]
            ).points,
            contentRevision: firstB.contentRevision &+ 1,
            cacheLineage: HAHistorySeriesCacheLineage(
                predecessorRevision: firstB.contentRevision,
                oldStart: 1,
                newStart: 0,
                count: 3
            )
        )

        func input(scope: String, history: HAHistorySeries) -> GraphRenderSeriesInput {
            GraphRenderSeriesInput(
                cacheScope: scope,
                entityID: entityID,
                name: "Shared owner",
                unit: "°C",
                color: graphBlue,
                history: history
            )
        }

        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(
            input(scope: "card-a", history: firstA),
            displayUnit: "°C"
        ))
        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(
            input(scope: "card-b", history: firstB),
            displayUnit: "°C"
        ))
        let resultA = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(
            input(scope: "card-a", history: updatedA),
            displayUnit: "°C"
        ))
        let resultB = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(
            input(scope: "card-b", history: updatedB),
            displayUnit: "°C"
        ))

        XCTAssertEqual(resultA.points.map(\.y), [20, 30, 40, 50])
        XCTAssertEqual(resultB.points.map(\.y), [60, 70, 80, 90])
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 2,
                incrementalPreparationCount: 2,
                cacheHitCount: 0
            )
        )
    }

    func testRollingTailWithMiddleCorrectionFallsBackToFullPreparation() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let first = GraphRenderSeriesInput(
            entityID: "sensor.corrected_rolling",
            name: "Corrected rolling",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.corrected_rolling",
                samples: [(0, "10"), (100, "20"), (200, "30"), (300, "40")]
            )
        )
        let correctedRolling = GraphRenderSeriesInput(
            entityID: "sensor.corrected_rolling",
            name: "Corrected rolling",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.corrected_rolling",
                samples: [(100, "20"), (200, "99"), (300, "40"), (400, "50")]
            )
        )

        _ = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [first], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))
        let updated = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [correctedRolling], unit: "°C", size: CGSize(width: 320, height: 160), scale: 1,
            zoomScale: 1, panFraction: 1
        ))

        XCTAssertEqual(updated.series.first?.points.map(\.y), [20, 99, 40, 50])
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 2,
                incrementalPreparationCount: 0,
                cacheHitCount: 0
            )
        )
    }

    func testRollingTailWithoutProjectionLineageFallsBackToFullPreparation() throws {
        GraphBitmapRenderer.resetPreparedSeriesCache()
        let first = GraphRenderSeriesInput(
            entityID: "sensor.no_lineage",
            name: "No lineage",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.no_lineage",
                samples: [(0, "10"), (100, "20"), (200, "30"), (300, "40")]
            )
        )
        let rolling = GraphRenderSeriesInput(
            entityID: "sensor.no_lineage",
            name: "No lineage",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.no_lineage",
                samples: [(100, "20"), (200, "30"), (300, "40"), (400, "50")]
            )
        )

        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(first, displayUnit: "°C"))
        let updated = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(rolling, displayUnit: "°C")
        )

        XCTAssertEqual(updated.points.map(\.y), [20, 30, 40, 50])
        XCTAssertEqual(
            GraphBitmapRenderer.preparedSeriesCacheStatistics(),
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 2,
                incrementalPreparationCount: 0,
                cacheHitCount: 0
            )
        )
    }

    func testMovingSyntheticBoundaryReusesProjectionLineageAndKeepsNewBoundary() async throws {
        let entityID = "sensor.moving_boundary"
        let initial = [
            compactGraphState("10", offset: 0),
            compactGraphState("20", offset: 100),
            compactGraphState("30", offset: 200),
            compactGraphState("40", offset: 300),
        ]
        var accumulator = HAHistoryStreamAccumulator(
            range: 250,
            now: { Date(timeIntervalSince1970: baseTimestamp + 400) }
        )
        let initialAccumulation = accumulator.processPublication(
            HAHistoryStreamMessage(states: [entityID: initial])
        )
        let rollingAccumulation = accumulator.processPublication(
            HAHistoryStreamMessage(states: [
                entityID: [compactGraphState("50", offset: 400)],
            ])
        )
        let projectionStore = HAHistoryProjectionStore(orderedEntityIDs: [entityID])
        let firstProjection = await projectionStore.series(from: HAHistoryStreamPublication(
            accumulation: initialAccumulation,
            ownerGeneration: 1
        ))
        let firstSeries = try XCTUnwrap(firstProjection?.first)
        let movedProjection = await projectionStore.series(from: HAHistoryStreamPublication(
            accumulation: rollingAccumulation,
            ownerGeneration: 1
        ))
        let movedSeries = try XCTUnwrap(movedProjection?.first)
        let first = graphInput(entityID: entityID, series: firstSeries)
        let movedBoundary = graphInput(entityID: entityID, series: movedSeries)

        XCTAssertEqual(
            movedSeries.cacheLineage,
            HAHistorySeriesCacheLineage(
                predecessorRevision: firstSeries.contentRevision,
                oldStart: 2,
                newStart: 1,
                count: 2
            )
        )

        GraphBitmapRenderer.resetPreparedSeriesCache()
        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(first, displayUnit: "°C"))
        let incremental = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(movedBoundary, displayUnit: "°C")
        )
        let incrementalStats = GraphBitmapRenderer.preparedSeriesCacheStatistics()

        GraphBitmapRenderer.resetPreparedSeriesCache()
        let coldOracle = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(movedBoundary, displayUnit: "°C")
        )

        XCTAssertEqual(incremental.points, coldOracle.points)
        XCTAssertEqual(incremental.points.map(\.y), [20, 30, 40, 50])
        XCTAssertEqual(try XCTUnwrap(incremental.points.first?.t), baseTimestamp + 150, accuracy: 0.001)
        XCTAssertEqual(
            incrementalStats,
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 1,
                incrementalPreparationCount: 1,
                cacheHitCount: 0
            )
        )
    }

    func testUnsortedCutoffGapFallsBackToExactFullGraphPreparation() async throws {
        let entityID = "sensor.unsorted_cutoff"
        var accumulator = HAHistoryStreamAccumulator(
            range: 15,
            now: { Date(timeIntervalSince1970: baseTimestamp + 40) }
        )
        let initial = accumulator.processPublication(HAHistoryStreamMessage(states: [
            entityID: [
                compactGraphState("10", offset: 10),
                compactGraphState("30", offset: 30),
                compactGraphState("20", offset: 20),
                compactGraphState("40", offset: 40),
            ],
        ]))
        let update = accumulator.processPublication(HAHistoryStreamMessage(states: [
            entityID: [compactGraphState("40", offset: 40)],
        ]))
        let store = HAHistoryProjectionStore(orderedEntityIDs: [entityID])
        let initialProjection = await store.series(from: HAHistoryStreamPublication(
            accumulation: initial,
            ownerGeneration: 1
        ))
        let initialSeries = try XCTUnwrap(initialProjection?.first)
        let updatedProjection = await store.series(from: HAHistoryStreamPublication(
            accumulation: update,
            ownerGeneration: 1
        ))
        let updatedSeries = try XCTUnwrap(updatedProjection?.first)
        XCTAssertNil(updatedSeries.cacheLineage)
        let projectionStatistics = await store.statistics()
        XCTAssertEqual(
            projectionStatistics,
            HAHistoryProjectionStoreStatistics(
                fullEntityProjectionCount: 2,
                incrementalEntityProjectionCount: 0,
                reusedEntityProjectionCount: 0
            )
        )

        let initialInput = graphInput(entityID: entityID, series: initialSeries)
        let updatedInput = graphInput(entityID: entityID, series: updatedSeries)
        GraphBitmapRenderer.resetPreparedSeriesCache()
        _ = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(initialInput, displayUnit: "µg/m³")
        )
        let prepared = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(updatedInput, displayUnit: "µg/m³")
        )
        let preparedStats = GraphBitmapRenderer.preparedSeriesCacheStatistics()

        GraphBitmapRenderer.resetPreparedSeriesCache()
        let oracle = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(updatedInput, displayUnit: "µg/m³")
        )
        XCTAssertEqual(prepared.points, oracle.points)
        XCTAssertEqual(prepared.points.map(\.y), [20, 30, 40, 40])
        XCTAssertEqual(
            preparedStats,
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 2,
                incrementalPreparationCount: 0,
                cacheHitCount: 0
            )
        )
    }

    func testHundredThousandPointMovingBoundaryMatchesColdOracleIncrementally() async throws {
        let entityID = "sensor.large_moving_boundary"
        let initial = (0..<99_999).map { offset in
            compactGraphState(
                String(offset % 100),
                offset: offset,
                syntheticBoundary: offset == 0
            )
        }
        var accumulator = HAHistoryStreamAccumulator(
            range: 99_997.5,
            now: { Date(timeIntervalSince1970: baseTimestamp + 99_999) }
        )
        let initialAccumulation = accumulator.processPublication(
            HAHistoryStreamMessage(states: [entityID: initial])
        )
        let rollingAccumulation = accumulator.processPublication(
            HAHistoryStreamMessage(states: [
                entityID: [compactGraphState("99", offset: 99_999)],
            ])
        )
        let rolling = try XCTUnwrap(rollingAccumulation.history[entityID])
        let projectionStore = HAHistoryProjectionStore(orderedEntityIDs: [entityID])
        let firstProjection = await projectionStore.series(from: HAHistoryStreamPublication(
            accumulation: initialAccumulation,
            ownerGeneration: 1
        ))
        let firstSeries = try XCTUnwrap(firstProjection?.first)
        let movedProjection = await projectionStore.series(from: HAHistoryStreamPublication(
            accumulation: rollingAccumulation,
            ownerGeneration: 1
        ))
        let movedSeries = try XCTUnwrap(movedProjection?.first)
        let first = graphInput(entityID: entityID, series: firstSeries)
        let movedBoundary = graphInput(entityID: entityID, series: movedSeries)

        XCTAssertEqual(movedSeries.cacheLineage?.predecessorRevision, firstSeries.contentRevision)
        XCTAssertEqual(movedSeries.cacheLineage?.oldStart, 2)
        XCTAssertEqual(movedSeries.cacheLineage?.newStart, 1)
        XCTAssertEqual(movedSeries.cacheLineage?.count, 99_997)

        GraphBitmapRenderer.resetPreparedSeriesCache()
        _ = try XCTUnwrap(GraphBitmapRenderer.preparedSeriesForTesting(first, displayUnit: "µg/m³"))
        let incrementalStart = DispatchTime.now().uptimeNanoseconds
        let incremental = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(movedBoundary, displayUnit: "µg/m³")
        )
        let incrementalNanoseconds = DispatchTime.now().uptimeNanoseconds - incrementalStart
        let incrementalStats = GraphBitmapRenderer.preparedSeriesCacheStatistics()

        GraphBitmapRenderer.resetPreparedSeriesCache()
        let fullStart = DispatchTime.now().uptimeNanoseconds
        let coldOracle = try XCTUnwrap(
            GraphBitmapRenderer.preparedSeriesForTesting(movedBoundary, displayUnit: "µg/m³")
        )
        let fullNanoseconds = DispatchTime.now().uptimeNanoseconds - fullStart

        XCTAssertEqual(incremental.points, coldOracle.points)
        XCTAssertEqual(incremental.points.count, rolling.count)
        XCTAssertEqual(try XCTUnwrap(incremental.points.first?.t), baseTimestamp + 1.5, accuracy: 0.001)
        XCTAssertEqual(incremental.points.first?.y, 1)
        XCTAssertEqual(
            incrementalStats,
            GraphPreparedSeriesCacheStatistics(
                fullPreparationCount: 1,
                incrementalPreparationCount: 1,
                cacheHitCount: 0
            )
        )
        print(
            "GRAPH_MOVING_BOUNDARY points=\(rolling.count) " +
            "incremental_ms=\(Double(incrementalNanoseconds) / 1_000_000) " +
            "full_oracle_ms=\(Double(fullNanoseconds) / 1_000_000)"
        )
    }

    func testViewportRenderSchedulerPublishesDuringEightMillisecondTokenStorm() {
        let scheduler = GraphViewportRenderScheduler { _ in
            Thread.sleep(forTimeInterval: 0.020)
            return nil
        }
        var deliveredTokens: [String] = []
        let eventCount = 24

        for index in 0..<eventCount {
            scheduler.schedule(viewportRequest(token: "viewport-\(index)")) { delivery in
                deliveredTokens.append(delivery.request.token)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.008))
        }

        let deliveriesBeforeGestureEnd = deliveredTokens.count
        let deadline = Date(timeIntervalSinceNow: 1)
        while deliveredTokens.last != "viewport-\(eventCount - 1)", Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }

        XCTAssertGreaterThanOrEqual(
            deliveriesBeforeGestureEnd,
            3,
            "A render slower than the event cadence must still publish intermediate frames."
        )
        XCTAssertEqual(deliveredTokens.last, "viewport-\(eventCount - 1)")
        XCTAssertEqual(scheduler.statistics.scheduledCount, eventCount)
        XCTAssertLessThan(scheduler.statistics.startedCount, eventCount)
        XCTAssertGreaterThan(scheduler.statistics.replacedPendingCount, 0)
        XCTAssertEqual(scheduler.statistics.maximumConcurrentCount, 1)
    }

    func testRenderMetricsSeparatePreparationAndBitmapStages() throws {
        let input = numericInput()
        var captured: GraphRenderMetrics?
        let result = try XCTUnwrap(GraphBitmapRenderer.render(
            inputs: [input],
            unit: "°C",
            size: CGSize(width: 320, height: 160),
            scale: 2,
            zoomScale: 1,
            panFraction: 1,
            metrics: { captured = $0 }
        ))
        let metrics = try XCTUnwrap(captured)

        XCTAssertEqual(metrics.inputPointCount, input.history.points.count)
        XCTAssertEqual(metrics.preparedPointCount, input.history.points.count)
        XCTAssertEqual(metrics.renderedPointCount, result.series.first?.points.count)
        XCTAssertEqual(metrics.bitmapByteCount, 640 * 320 * 4)
        XCTAssertGreaterThan(metrics.totalNanoseconds, 0)
        XCTAssertGreaterThan(metrics.pathConstructionNanoseconds, 0)
        XCTAssertGreaterThan(metrics.pathStrokeNanoseconds, 0)
    }

    func testCancelledRenderStopsBeforePublishingABitmap() async {
        let entityID = "sensor.cancelled_render_\(UUID().uuidString)"
        let points = (0..<10_000).map { index -> HAHistoryPoint in
            let timestamp = String(
                format: "2026-01-01T%02d:%02d:%02dZ",
                index / 3_600,
                (index % 3_600) / 60,
                index % 60
            )
            return HAHistoryPoint(
                entityId: entityID,
                state: String(index % 100),
                attributes: nil,
                lastChanged: timestamp,
                lastUpdated: timestamp
            )
        }
        let input = GraphRenderSeriesInput(
            entityID: entityID,
            name: "Cancellation fixture",
            unit: "µg/m³",
            color: graphBlue,
            history: HAHistorySeries(entityID: entityID, points: points)
        )
        let task = Task.detached {
            GraphBitmapRenderer.render(
                inputs: [input],
                unit: "µg/m³",
                size: CGSize(width: 496, height: 178),
                scale: 2,
                zoomScale: 1,
                panFraction: 1
            )
        }

        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    private func numericInput() -> GraphRenderSeriesInput {
        GraphRenderSeriesInput(
            entityID: "sensor.room_temperature",
            name: "Room temperature",
            unit: "°C",
            color: graphBlue,
            history: history(
                entityID: "sensor.room_temperature",
                samples: [
                    (0, "20"),
                    (900, "22"),
                    (1_800, "19"),
                    (2_700, "27"),
                    (3_600, "24"),
                ]
            )
        )
    }

    private func timelineInput() -> GraphRenderSeriesInput {
        GraphRenderSeriesInput(
            entityID: "switch.test",
            name: "Test switch",
            unit: HAHistoryGraphClassifier.stateUnit,
            color: graphBlue,
            history: history(
                entityID: "switch.test",
                samples: [
                    (0, "off"),
                    (900, "on"),
                    (1_800, "unknown"),
                    (2_700, "unavailable"),
                ]
            ),
            windowStart: baseTimestamp,
            windowEnd: baseTimestamp + 3_600
        )
    }

    private func viewportRequest(token: String) -> GraphViewportRenderRequest {
        GraphViewportRenderRequest(
            token: token,
            dataToken: "stable-data",
            inputs: [],
            unit: "µg/m³",
            size: CGSize(width: 496, height: 178),
            scale: 2,
            zoomScale: 4,
            panFraction: 0.5
        )
    }
}

@MainActor
final class CardReferenceContractTests: XCTestCase {
    func testGraphHoverOverlayPolicyDefaultsEnabledAndAcceptsEnvironmentOverride() {
        let policy = GraphInteractionPolicy(
            hoverOverlayDefault: .enabled,
            hoverOverlayEnvironmentVariable: "NATIVEHA_GRAPH_HOVER_OVERLAY"
        )

        XCTAssertTrue(policy.hoverOverlayEnabled(environment: [:]))
        XCTAssertFalse(policy.hoverOverlayEnabled(environment: ["NATIVEHA_GRAPH_HOVER_OVERLAY": "0"]))
        XCTAssertFalse(policy.hoverOverlayEnabled(environment: ["NATIVEHA_GRAPH_HOVER_OVERLAY": "off"]))
        XCTAssertTrue(policy.hoverOverlayEnabled(environment: ["NATIVEHA_GRAPH_HOVER_OVERLAY": "1"]))
        XCTAssertTrue(policy.hoverOverlayEnabled(environment: ["NATIVEHA_GRAPH_HOVER_OVERLAY": "invalid"]))
    }

    func testProductionWebSocketPolicyKeepsTimeoutAndReceiveBoundIndependent() {
        XCTAssertEqual(AppConfig.webSocketPolicy.commandTimeout, 10)
        XCTAssertEqual(
            AppConfig.webSocketPolicy.receivePolicy.maximumMessageBytes,
            32 * 1_024 * 1_024
        )
        XCTAssertEqual(AppConfig.webSocketPolicy.subscriptionDeliveryCapacity, 256)
        XCTAssertEqual(AppConfig.webSocketPolicy.maximumConcurrentCallbackTasks, 4)
    }

    func testHistoryCardUsesApprovedGlobalRangeWithoutMutatingRawHours() {
        let model = DashboardViewModel()
        model.selectedGraphHours = 1
        let card = LovelaceCard(
            type: "history-graph",
            entities: [LovelaceEntityRef(entity: "sensor.temperature")],
            hoursToShow: 12
        )

        let oneHourKey = model.historyKey(for: card)
        model.selectedGraphHours = 12
        XCTAssertNotEqual(model.historyKey(for: card), oneHourKey)
        XCTAssertEqual(card.hoursToShow, 12)
        XCTAssertEqual(AppConfig.graphTimeRangePolicy.scope, .global)
    }
}

private let baseTimestamp = 1_767_225_600.0 // 2026-01-01 00:00:00 UTC
private let graphBlue = GraphColor(red: 0.26, green: 0.47, blue: 0.95, alpha: 1)

private func history(entityID: String, samples: [(Int, String)]) -> HAHistorySeries {
    HAHistorySeries(
        entityID: entityID,
        points: samples.map { offset, state in
            let hour = offset / 3_600
            let minute = (offset % 3_600) / 60
            let second = offset % 60
            let timestamp = String(
                format: "2026-01-01T%02d:%02d:%02dZ",
                hour,
                minute,
                second
            )
            return HAHistoryPoint(
                entityId: entityID,
                state: state,
                attributes: nil,
                lastChanged: timestamp,
                lastUpdated: timestamp
            )
        }
    )
}

private func graphInput(entityID: String, series: HAHistorySeries) -> GraphRenderSeriesInput {
    GraphRenderSeriesInput(
        entityID: entityID,
        name: entityID,
        unit: "µg/m³",
        color: graphBlue,
        history: series
    )
}

private func compactGraphState(
    _ state: String,
    offset: Int,
    syntheticBoundary: Bool = false
) -> HACompactHistoryState {
    let timestamp = baseTimestamp + Double(offset)
    return HACompactHistoryState(
        state: state,
        attributes: [:],
        lastChangedSeconds: syntheticBoundary ? nil : timestamp,
        lastUpdatedSeconds: timestamp
    )
}

struct RGBA: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

}

struct RGBAPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: CGImage) throws {
        let pixelWidth = image.width
        let pixelHeight = image.height
        var storage = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let rendered = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard rendered else {
            throw PixelError.contextCreationFailed
        }
        width = pixelWidth
        height = pixelHeight
        bytes = storage
    }

    func count(near target: RGBA, tolerance: UInt8) -> Int {
        count { $0.isNear(target, tolerance: tolerance) }
    }

    func count(where predicate: (RGBA) -> Bool) -> Int {
        stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { count, offset in
            let pixel = RGBA(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            )
            if predicate(pixel) {
                count += 1
            }
        }
    }

    func mostCommon(limit: Int) -> [(RGBA, Int)] {
        var counts: [RGBA: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let pixel = RGBA(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
            counts[pixel, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    func containsBluePixel(nearX x: Int, y: Int, radius: Int) -> Bool {
        let minX = max(x - radius, 0)
        let maxX = min(x + radius, width - 1)
        let minY = max(y - radius, 0)
        let maxY = min(y + radius, height - 1)
        guard minX <= maxX, minY <= maxY else {
            return false
        }
        let xRange = minX...maxX
        let yRange = minY...maxY
        for row in yRange {
            for column in xRange {
                let offset = (row * width + column) * 4
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                if blue > red + 80 && blue > green + 45 {
                    return true
                }
            }
        }
        return false
    }

    private enum PixelError: Error {
        case contextCreationFailed
    }
}

private extension RGBA {
    func isNear(_ other: RGBA, tolerance: UInt8) -> Bool {
        abs(Int(red) - Int(other.red)) <= Int(tolerance) &&
            abs(Int(green) - Int(other.green)) <= Int(tolerance) &&
            abs(Int(blue) - Int(other.blue)) <= Int(tolerance) &&
            abs(Int(alpha) - Int(other.alpha)) <= Int(tolerance)
    }
}
