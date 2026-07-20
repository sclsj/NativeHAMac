---
schema: nativeha-evidence/v1
module: "09"
title: Graph revision scheduling and engine benchmarks
plan: ../../rescue-plan/module-09-graph-rendering.md
status: bounded-follow-up-validated-broader-module-unresearched
contract_revision: 1
depends_on: ["01"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: cd45663ef6ae41902f2d0a4f16a8467a17be8a53
graph_file: ../generated/module-09.dependencies.json
graph_fingerprint: 4b7b0f295034f3d44db1b2eb77c57b1105971ff555d0d83e4d2f58406b817458
last_validated: 2026-07-20
---

# Module 09 bounded follow-up evidence

## Scope delta

This packet covers only the cache-warming regression test and the three-engine
performance benchmark requested after the graph-smoothness investigation. It
does not claim that broader Module 09 parity is researched or complete, and it
does not authorize a prepared-cache concurrency/correctness redesign.

Commit `5861848ba9e6b1c5108596cb194870d66822a6e7` fixed the measured lag by
submitting every changed data revision to prepared-series maintenance before
visual cancellation, debounce, off-live-edge suppression, or renderer-specific
scheduling. Rendering may skip revision N; preparation may not, because N+1's
incremental lineage names N as its immediate predecessor.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle rules | Swift owner | Verification |
|---|---|---|---|---|---|
| C09-WARM-01 | Cache contains N-1 and data revision N arrives | N is submitted to production prepared-series maintenance before any visual scheduling decision. | Visual cancellation, debounce, and engine selection do not own maintenance. | `BitmapLineChart` plus an internal revision-preparation scheduler | Seed N-1; submit N without rendering it; submit N+1; expect one full and two incremental preparations. |
| C09-WARM-02 | N and N+1 are submitted rapidly for one card/cache scope | Preparation consumes N before N+1. | FIFO is stable for the scheduler's lifetime. | Revision-preparation scheduler | Await the N+1 completion and assert exact cache counters. |
| C09-WARM-03 | The visual frame for N is skipped/superseded | N+1 remains incremental solely because maintenance consumed N. | Cache semantics outside this scheduling invariant are unchanged. | Existing `GraphPreparedSeriesCache` | Bypassing N deterministically changes the counters to two full and zero incremental preparations. |
| C09-BENCH-01 | A preprepared frame is sent to any supported engine | Report actual production-side pure-render work for Core Graphics, Canvas, and Metal with `n`, p50, p95, and max. | Identical input, viewport sequence, iterations, scale, and warm-up. | Production renderer helpers plus benchmark harness | Every engine returns nonempty work/output. |
| C09-BENCH-02 | A consecutive logical update is submitted | Present-ready timing begins before dispatch/cache access and ends after preparation, downsampling/geometry, renderer dispatch, and requested-frame completion. | Match each submitted frame with its completion. Compositor scanout is excluded and must not be claimed. | Production graph preparation and engine completion adapters | All requested frames complete; report `n`, p50, p95, and max plus optional stages. |
| C09-BENCH-03 | Compare 1h and 24h cases | All six engine/window cases use the same live series, revision sequence, viewport sequence, size, scale, iteration count, and warm-up policy. | Do not mutate global renderer configuration; use explicit engine injection or restore changes. | Graph benchmark target | Assert fixture metadata and completion counts; no machine-specific paths or pass/fail latency threshold. |

## Source anchors

NativeHA baseline at `cd45663ef6ae41902f2d0a4f16a8467a17be8a53`:

- `CardViews.swift::BitmapLineChart.scheduleRenders`, blob
  `ceda8a0f8d56aeaa55024f3f690a485567b03299`, SHA-256
  `5aeda11d6d514d14d49b0a7a0a7f26f8b9d4c64f9b78b7ebc132be7a64ec8d1c`.
- `GraphRendering.swift::GraphBitmapRenderer` and
  `GraphPreparedSeriesCache.series/incrementallyUpdate`, blob
  `aa6b737a7a909ceb798ebbe4c9bcf0935132ad8d`, SHA-256
  `37b9e0b073f255e01bcbef5368ec68fadeaac7dd787667c4cf38a1f08ec7ae2c`.
- `GraphRenderScheduling.swift::GraphViewportRenderScheduler`, blob
  `b0587a7c9309e63d9dcfbc8aa40e193dc7a552b8`, SHA-256
  `340c496a1b9c7ee9ffa0f74e359476481b485ffd86a460b77467b9ed068d7ef0`.
- `Models.swift::HAHistorySeries/HAHistorySeriesCacheLineage`, blob
  `38df0c63831e1ebaf3f713634f7410e6184cdf49`, SHA-256
  `03655999a1e1acb9f1308e9c92c67bc665f356a35588688cf5202c3a8045a7cc`.
- `GraphMetalRenderer.swift::GraphMetalRenderer.draw`, blob
  `2f631c81510a0e9ade322b54a5bf0c93791e4460`, SHA-256
  `c7d03c03cf920df9fd97ed5b702e7dc353b3d09a7bc59a81382b46608e41ec14`.
- `GraphEngineBenchmarks.swift::GraphEngineBenchmarks`, blob
  `8690053ef09b4a2244a92c8234057b3ba61825da`, SHA-256
  `d22804804277957362cf673abfbaf17010560a02edbbf60880aedc44232b66b5`.

hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`:

- `src/data/history.ts::HistoryStream.processMessage`, blob
  `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`.
- `src/panels/lovelace/cards/hui-history-graph-card.ts::_subscribeHistory`,
  blob `9b6bb306ca29ecfc4e028cab468c5f826a0ed1a5`.
- `src/components/chart/state-history-chart-line.ts::willUpdate/_generateData`,
  blob `4f3e4bb3fa7fb6a479569c17a59954384edb2282`.
- `src/components/chart/state-history-chart-line-data.ts::generateStateHistoryChartLineData`,
  blob `fc4a639d3d439d38bddca475fa2c623e43d18950`.
- `src/components/chart/ha-chart-base.ts::willUpdate/_getSeries/_setChartOptions`,
  blob `e2b455b28633090472d469c539cff0c0c217abb6`.

The reference has no equivalent NativeHA prepared-series revision cache. Its
continuous history callbacks regenerate changed chart data. FIFO cache warming
is a measured native scheduling choice that preserves that observable behavior.

## Dependency traces and boundaries

The generated graph is the rebuildable discovery artifact. Traversal starts at
the history accumulator, Lovelace graph consumer, line-data generator, line
chart, and chart base. It stops at one level because the relevant contract is
continuous changed-data consumption; ECharts internals, broader card options,
tooltip parity, and other visual behavior do not determine this scheduling fix.

## Native mapping

| Contract | Swift path | Symbol/type | Ownership/state | Notes |
|---|---|---|---|---|
| C09-WARM-01..03 | `GraphRenderScheduling.swift`, `CardViews.swift` | revision-preparation scheduler and `BitmapLineChart.scheduleRenders` | One stable FIFO owner per chart | Extract the existing warmer; do not redesign shared-cache storage. |
| C09-BENCH-01..03 | `GraphRendering.swift`, `GraphMetalRenderer.swift`, `CardViews.swift`, `Benchmarks/GraphRendering` | engine preparation/render completion seams and benchmark | Explicit engine per case; persistent per-engine harness | Pure-render and present-ready distributions remain separate. |

## Decisions and native deviations

| ID | Decision | Allowed reason | Preserved semantics | Test | Status |
|---|---|---|---|---|---|
| D09-01 | Maintain every data revision independently from cancellable/debounced visual frames. | Measured performance benefit | Every accepted history revision remains available to the next incremental preparation. | C09-WARM-01..03 | implemented by `5861848`; regression seam pending |
| D09-02 | Name the end-to-end automated endpoint `present-ready`. | Platform limitation | Measures all NativeHA work through requested renderer completion without claiming macOS compositor scanout. | C09-BENCH-02 | pending |

## Validation

### Offline deterministic tests

- `swift test --filter 'NativeHAMacTests.GraphRenderingTests/testSkippedVisualRevisionStillWarmsImmediatePredecessorForNextRevision'`
  passed. The production FIFO scheduler produced `full=1, incremental=2`; the
  explicit bypass control produced `full=2, incremental=0`.
- `swift test -c release --filter GraphRenderingBenchmarkTests` passed all
  three deterministic benchmark tests.
- `swift test --filter NativeHAMacTests.GraphRenderingTests` ran 19 tests. The
  new regression passed; three pre-existing/out-of-scope graph failures remain:
  numeric time bounds, a stale step-end expected-failure annotation, and a nil
  zoom/pan result.

### Read-only live smoke

The authorized read-only release benchmark fetched four configured SPS30
series for both 1h (13,988 points) and 24h (335,536 points). No server state
was changed.

### Visual and animation oracle

N/A: this follow-up validates frame completion and nonempty renderer output,
not graph visual-parity changes.

### Performance and lifecycle

`NATIVEHA_LIVE_GRAPH_BENCHMARK=1 NATIVEHA_GRAPH_BENCH_ITERATIONS=20 swift test
-c release --filter GraphEngineBenchmarks` passed Metal, Core Graphics, and
Canvas at 1h/24h. All 120 present-ready frames and 120 pure-render samples
completed with nonempty artifacts. Exact distributions and stage p50 values
are recorded in `Benchmarks/GraphRendering/results.md`. The present-ready
endpoint excludes compositor scanout.

## Open questions and risks

- `GraphPreparedSeriesCache` releases its lock while preparing and may admit
  unrelated interleavings/stale stores. That broader correctness work is
  explicitly deferred.
- Actual compositor presentation is not available as a deterministic XCTest
  boundary; results must say present-ready.
- The current default renderer is pre-existing worktree state and is not a
  benchmark decision.

## Handoff

The requested bounded follow-ups are validated. Broader Module 09 parity and
the prepared-cache concurrency/correctness redesign remain unresearched and
must start as their own later task; do not treat this packet as completion of
Module 09.

## Change log

- 2026-07-20: Created bounded research packet for the cache-warming regression
  and engine benchmark follow-ups. Broader Module 09 remains unresearched.
- 2026-07-20: Added the production FIFO regression seam/test and symmetric live
  engine benchmark; recorded validation while leaving broader Module 09 open.
