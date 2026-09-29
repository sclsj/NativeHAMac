---
schema: nativeha-evidence/v1
module: "09"
title: Graph revision preparation and asynchronous render scheduling
plan: ../../rescue-plan/module-09-graph-rendering.md
status: bounded-async-repair-verified-open-stale-viewport-fallback-broader-module-unresearched
contract_revision: 3
depends_on: ["01"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 9291da336d2f068c39c4924fed3add4c52c27f85
graph_file: ../generated/module-09.dependencies.json
graph_fingerprint: "712b2dbf3943a23fd9eec8dba19531a5eeca5a90b4ab7e358d3b8988a89c938c"
last_validated: 2026-09-11
---

# Module 09 bounded async-repair evidence

## 2026-09-11 readiness follow-up and deferral

The [readiness audit](../../audits/2026-09-11-readiness.md) reproduces unbounded axis generation on synthetic input, diagonal numeric lines despite a passing step test, future hover values, and empty rendering when a viewport lies between numeric samples. The user deferred the axis finding pending later work; live HA reachability is unestablished. Graph semantics and the weak conformance oracle will be addressed in a dedicated graphing module with further product scope to come. These are open findings, not prerequisites for Module 08. Preserve this packet's verified off-main scheduling and safe lineage fallback. No graph implementation, contract, or expected-failure test is changed by the bootstrap consolidation.

## Scope delta

This packet validates only the SPS30 rolling-window repair: move expensive prepared-series and bitmap work off the main thread without losing cache lineage when visual frames are coalesced. Broader Module 09 visual parity is still unresearched.

The repair replaces the synchronous body renderer and separate background warmer with `GraphChartRenderCoordinator`, one serial off-main owner per chart. `GraphHistoryRevisionFeed` publishes accepted projections before the `@Published` view invalidation, the coordinator drains data revisions FIFO, and only the newest visual request is retained. Coordinator owner/generation scope prevents another chart or a reset generation from interleaving with the same prepared-cache key.

Losslessness has an explicit lifecycle boundary. While a chart observer is mounted/subscribed, every accepted publication is delivered synchronously and queued FIFO. Before an observer subscribes, the feed retains only its latest snapshot and replays that snapshot at subscription. This is safe because a new coordinator generation starts from a cold/re-keyed cache (or its exact safe fallback); the packet does not claim that unmounted charts retain every intermediate revision.

The renderer now consumes bounds-checked `HAHistorySeriesCacheLineage` when its cached numeric source is the exact immediate predecessor. Timestamp alignment remains an instrumented safe fallback for skipped/unmounted/reset/corrected or unsupported shapes. Current immutable arrays and min/max construction still make large-window preparation proportional to retained size, but it no longer blocks the main actor.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle rules | Native owner | Verification |
|---|---|---|---|---|---|
| C09-ASYNC-01 | An accepted projected numeric data revision arrives | Submit it to prepared-series maintenance without synchronously preparing or drawing from SwiftUI body/main actor. | Heavy parsing, overlap application, min/max construction, viewport preparation, and bitmap work are off-main. Main actor captures lightweight immutable request state and installs a completed result only. | One stable per-chart revision/render coordinator | Hooks assert preparation/render are never on main; a 100k-point publication does not block a gated main-actor probe. |
| C09-ASYNC-02 | Revisions N and N+1 are accepted for one mounted/subscribed chart/cache scope | Prepared state advances N before N+1. | While subscribed, data revisions are FIFO and are not dropped by visual debounce, cancellation, viewport replacement, or renderer choice. Before subscription, retain/replay only the latest snapshot; the newly re-keyed coordinator starts cold/fallback-safe. | `DashboardViewModel.startHistory`, `GraphHistoryRevisionFeed`, and stable chart coordinator | Gate N, submit N+1, and prove N+1 cannot prepare first. Publication-storm and latest-before-subscribe replay tests distinguish accepted mounted revisions from visual frames. |
| C09-ASYNC-03 | Several viewport/data render requests become obsolete while preparation is busy | Visual frames may coalesce to the newest requested data generation and viewport. | Coalescing render work must not coalesce or reorder the FIFO data-maintenance stream. Rendering revision N is optional; consuming N is not. | Same coordinator, with FIFO data work and one overwriteable latest visual request | Submit N/N+1/N+2, render only N+2, assert one initial full preparation followed by exact incremental advances and exact final image token. |
| C09-ASYNC-04 | Cached revision equals `cacheLineage.predecessorRevision` | Apply the supplied `oldStart`, `newStart`, and `count` as the authoritative overlap proof; do not search timestamps or compare the complete retained overlap. | Validate bounds and the cached numeric one-to-one-source invariant. A missing/mismatched lineage, reconnect/reset generation, nonnumeric/timeline shape, correction, or invalid bounds takes a safe off-main rebuild/fallback path. | Prepared-series owner | Moving-boundary oracle tests prove exact output, no alignment scan, and no routine full fallback; deliberate mismatch/correction proves one safe rebuild. |
| C09-ASYNC-05 | Preparation and rendering target the same cache key | They execute under one same-key owner and cannot store out of revision order. | No synchronous renderer, background warmer, detached renderer, benchmark adapter, or lifecycle task may independently mutate the production cache for that same key. Different cache scopes may proceed independently. | Coordinator plus prepared-cache API boundary | Deterministically interleave gated N and N+1 work and assert the final stored revision is N+1; stress two distinct cache scopes and assert isolation. |
| C09-ASYNC-06 | Chart disappears, changes owner generation/range, reconnects, or receives a stale completion | Stale work cannot publish or seed the new generation's lineage. | Cancel/drop pending visuals, close the old revision feed, and reset or re-key ownership before accepting the new generation. Completed old work cannot overwrite current prepared or visible state. | Chart lifecycle/coordinator generation | Disappearance, range-switch, reconnect, and late-completion tests. |
| C09-BENCH-01 | The repaired 1h/12h/24h rolling path is benchmarked | Report present-ready and preparation stages separately for Core Graphics (primary current engine); existing other-engine coverage remains valid but is not the decision driver. | Production-shaped initial full load plus many one-point/moving-boundary revisions; identical source and viewport sequence for comparisons. | Existing graph benchmark target | Exact cold-oracle equality; counts for full, incremental, cache hit, alignment fallback, and maximum concurrency; p50/p95/max. |

## Reference contracts

The reference has no equivalent predecessor-sensitive prepared-series cache. `HistoryStream.processMessage` consumes each WebSocket callback into combined history, and `HuiHistoryGraphCard._subscribeHistory` computes/merges the changed history for its chart. `StateHistoryChartLine.willUpdate` regenerates data when its `data` property changes; `HaChartBase.willUpdate` rebuilds series and calls `setOption`. Lit/ECharts may avoid obsolete visual work without maintaining a NativeHA cache whose correctness depends on rendering every intermediate revision.

Therefore FIFO prepared-state maintenance and exact lineage are native correctness/performance mechanisms, not a literal frontend structure. The observable behavior to preserve is that the latest accepted history and viewport eventually produce the latest correct graph while interaction remains responsive.

## Source anchors

NativeHA implementation worktree based on `acf385133e2c875cc0d0d96c9a85125a87c11bcf` (the pre-existing dirty `AppConfig.swift` Core Graphics setting is preserved; all implementation/test anchors below are pinned by generated-graph worktree hash):

- `DashboardViewModel.swift::startHistory`, worktree blob `af2a3ba3453e62c783041f6a157e948964e5fc3e`, SHA-256 `7c813a3d61a9492f371f2079f5f78b59503ceaf1429ad3a25f057398146efed0`.
- `CardViews.swift::UnitGraph/BitmapLineChart`, worktree blob `eac04368a44758c49798ab5b95f6a8e726943437`, SHA-256 `ae9b4078f2b687bc459a072c8af673745cd2a6c31fb13cac2ac1f876f2632748`.
- `GraphRenderScheduling.swift::GraphHistoryRevisionFeed/GraphChartRenderCoordinator/GraphViewportRenderScheduler`, worktree blob `8485459478d6aed9557e7fd76b18bc371112894c`, SHA-256 `9812a7a172c7f9c133f163a7c314095d0fba0a1b68185a8080d6d6afbbe87b01`.
- `GraphRendering.swift::GraphBitmapRenderer/GraphPreparedSeriesCache`, worktree blob `a2666396d811547431710302f8f31244a8ca5794`, SHA-256 `6fdeb14608f5a396a800fba83ce40df034e0cc93fde90b8ddaccfbaa1d22e373`.
- `HomeAssistantHistoryStream.swift::HAHistoryProjectionStore`, blob `8cac19f68aea0fca6b17af7619c03bdfa528880c`, SHA-256 `fbaf6d5bad0a7e7284c1716b1182c4167f229fb221c089374fed8e6ec1ed1728`.
- `Models.swift::HAHistorySeries/HAHistorySeriesCacheLineage`, blob `de4597fdfc470de2cdc2d2d1f071ae56ba3a799d`, SHA-256 `e5f00bf9126282c3223669599085a40c20a21e44037dfc9f4bb5a0e08ee15354`.
- `GraphRenderingTests.swift`, worktree blob `6a1db1ceb23eeb7cf91fa3fdfb349886b8b12d92`, SHA-256 `bef42158af95724dcb071c84da4839f29719846e16c9709fd38fcc6c78d0f469`.
- `HistoryStreamIntegrationTests.swift`, worktree blob `6b5a0f7f5efd7de20596bff30bd114f12e99cd73`, SHA-256 `6d68fb5059976999aeb7395e4ab97935000c9065a859091d31e9e4dde98295d1`.
- `GraphEngineBenchmarks.swift`, worktree blob `768ef551ba575dd2c5543f671d210961142be651`, SHA-256 `dae1c257e3eb2bb8e53de17b2b89aa56b635a44f64f77dddeef6e4c9c4f44bce`.

hass-frontend at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`:

- `src/data/history.ts::HistoryStream.processMessage`, blob `5a3c3e8f8fa02c7a081a1ddb0fea875bd40147e2`.
- `src/panels/lovelace/cards/hui-history-graph-card.ts::_subscribeHistory`, blob `9b6bb306ca29ecfc4e028cab468c5f826a0ed1a5`.
- `src/components/chart/state-history-chart-line.ts::willUpdate/_generateData`, blob `4f3e4bb3fa7fb6a479569c17a59954384edb2282`.
- `src/components/chart/state-history-chart-line-data.ts::generateStateHistoryChartLineData`, blob `fc4a639d3d439d38bddca475fa2c623e43d18950`.
- `src/components/chart/ha-chart-base.ts::willUpdate/_getSeries/_setChartOptions`, blob `e2b455b28633090472d469c539cff0c0c217abb6`.

## Native mapping and required ownership

| Contract | Swift target | Required ownership | Important boundary |
|---|---|---|---|
| C09-ASYNC-01..03 | `DashboardViewModel`, `CardViews`, `GraphRenderScheduling` | One stable coordinator per chart/cache scope; mounted FIFO revision input plus latest-only visual request | Feed publishes before view invalidation; pre-subscription storage is latest-only and cold/fallback-safe. |
| C09-ASYNC-04..05 | `GraphRendering`, `GraphRenderScheduling` | The coordinator is the only same-key prepared-cache caller; direct lineage fast path when predecessor matches | A detached visual renderer must consume already coordinated/prepared state or run on the same serial owner; it must not independently call the shared cache. |
| C09-ASYNC-06 | `DashboardViewModel`, `UnitGraph`, coordinator | Generation-scoped lifetime | Range/reconnect identity is part of ownership; no lineage across reset. |
| C09-BENCH-01 | `Benchmarks/GraphRendering` | Persistent production-shaped coordinator | Core Graphics is the user's primary path; Metal remains WIP. |

## Decisions and native deviations

| ID | Decision | Allowed reason | Preserved semantics | Test | Status |
|---|---|---|---|---|---|
| D09-01 | Maintain every accepted publication while a chart observer is mounted independently from coalescible visual frames; retain/replay latest only before subscription. | Native cache correctness with bounded lifecycle ownership | Latest accepted history remains renderable; a new generation starts cold/fallback-safe. | C09-ASYNC-02..03 | implemented and verified |
| D09-02 | Replace synchronous body rendering and the separate warmer with one off-main same-key owner. | Measured responsiveness and race removal | Same final graph; main actor only installs current completed output. | C09-ASYNC-01, C09-ASYNC-05 | implemented and verified |
| D09-03 | Restore exact immediate-lineage consumption as the normal numeric rolling path; retain a safe off-main fallback. | Upstream already proved the overlap | Corrections, reconnects, skipped pre-subscription revisions, and unsupported shapes still rebuild exactly. | C09-ASYNC-04 | implemented and verified |
| D09-04 | Coalesce obsolete visual frames, not mounted data-state transitions. | Interaction priority | Final data generation and viewport settle exactly. | C09-ASYNC-03, C09-ASYNC-06 | implemented and verified |

## Validation

### Offline deterministic and integration

- Focused graph regressions passed. They cover FIFO off-main preparation, latest-only visual replacement, one maximum concurrent coordinator worker, stale completion rejection, lifecycle-generation token changes, 100-event mounted feed delivery, latest-event replay for a later subscriber, direct lineage counters, timestamp-alignment fallback, invalid equal-timestamp suffix rejection, moving boundaries, cold-oracle equality, and scoped-owner isolation.
- Focused history integration passed. Initial/reset, normal ordered, and out-of-order reset publications reach the graph feed with flags `[true, false, true]` at the accepted projection boundary.
- The release `NativeHAMac` product builds with the asynchronous coordinator.

### Read-only live and performance

- The release live benchmark passed against the actual configured CO2/VOC history-card entities at 1h and 24h using the user's primary Core Graphics path. Consecutive preparation statistics distinguish exact-lineage updates from alignment fallback and retained exact output.
- The 24h Core Graphics preparation stage remains about 95 ms on this machine. This bounded repair does not claim O(1) rolling storage; it verifies that the work is serialized off-main and no longer freezes chart/UI interaction.
- A later 12-minute debug launch at the verified coordinator baseline recorded 1,897 cases where a stale visual request could not align against the already newer prepared cache and safely fell back to full preparation. The work was off-main, so this does not invalidate the repaired main-thread ownership or rendered-data correctness, but repeated O(window) background work remains a measurable CPU/latency risk for the daily-use PoC.
- Two attempted shortcuts were independently rejected and reverted. Numeric comparison of `contentRevision` is invalid because revisions are content digests, and comparing `lastTimestamp` cannot prove ancestry across corrections, equal-timestamp changes, rolling eviction, state timelines, or feedless detail graphs. Existing same-shape and rolling-tail correctness oracles pass again after the reverts.

### Context and scope

- The refreshed graph resolves 41 nodes / 241 edges, has no unresolved nodes, is not truncated, and has fingerprint `5e59d9f50ca2c34250a8924745a692cfa3ed2eed6c3cf2e59ae6b39449dde840`.
- Resolver self-test passes at 28 nodes / 59 edges. Context check and `git diff --check` are green.
- Visual step/hover/axis/legend parity and the rest of Module 09 were not part of this repair or verification and remain unresearched.

## Bounded post-Module 05 anchor maintenance — 2026-08-31

The pre-refresh checker was yellow for exactly seven shared or previously advanced native anchors: `Models.swift`, `AppConfig.swift`, `CardViews.swift`, `DashboardViewModel.swift`, `GraphRenderScheduling.swift`, `GraphRenderingTests.swift`, and `HistoryStreamIntegrationTests.swift`. The exact accepted Module 05 diff, the intervening already-green Module 04/12 changes, and the final Module 05 independent evidence were inspected against this bounded contract revision 3. The pinned frontend history/chart sources are unchanged; broader Module 09 was not researched.

Module 05 moves graph revision-feed dictionary storage into the synchronous MainActor `DashboardHistoryCoordinator` façade. The manifest now pins that owner and replaces the obsolete `startHistory` symbol with the current `beginHistoryStartup`/`runHistoryStartup` publication boundary in `DashboardViewModel`. Accepted projections still publish to the feed before `@Published` history, mounted data revisions remain FIFO, visual requests remain latest-only, and disappearance/stop invalidates feeds, mounts, coordinator generations, and render work before late results can install. Core Graphics remains primary. The changed configuration/render/test anchors preserve the approved coordinator/cache policies and their existing exact lineage/fallback oracles.

Regeneration is green at 41 nodes / 241 edges, one cycle, zero unresolved edges, no truncation, and fingerprint `da934dc5939cea850cf2c1eb9567350ce240c8f59e71a3d6a378fa9982259c8a`. The resolver self-test passes at 31 nodes / 61 edges with fingerprint `da06a3bfa032082ad19743e076372c8a73181f37d75f4f468b60395000afa13d`. The fresh final Module 05 verifier passed the complete graph/history/lifecycle regressions within its 237-test full suite, with three authorized skips and zero failures, plus release, GUI, and authorized read-only live smoke. This is anchor maintenance only: the bounded asynchronous repair remains verified, the stale-viewport correctness-safe but expensive fallback remains open, and broader Module 09 remains unresearched. No hash, `contentRevision`, endpoint timestamp, or first/last timestamp may infer freshness. No Swift or test file was edited by this maintenance.

## Remaining risks and boundaries

- A chart that is not mounted does not retain every intermediate publication; it receives only the latest replay at subscription and safely starts a new cold/fallback generation. Do not describe feed losslessness without this observer-lifecycle qualification.
- Exact lineage removes the O(n) equality/alignment proof, but current immutable arrays and `GraphMinMaxCache` still copy/rebuild O(window) data. The verified 24h preparation cost is about 95 ms off-main. A chunked/ring representation remains a later measured optimization.
- Timeline/nonnumeric, correction, reconnect/reset, skipped pre-subscription, and invalid-lineage shapes intentionally use the safe fallback rather than exact numeric lineage.
- The coordinator scopes cache ownership by stable owner and generation. New production paths must not bypass that owner and mutate its effective key.
- A pending visual request can contain an older history snapshot than the coordinator has already prepared. The cache must not return a different fingerprint merely because an endpoint or digest appears numerically newer. The smallest sound follow-up is for the coordinator to retain the latest accepted inputs per entity/generation and resolve pending viewport renders against those inputs while preserving viewport metadata. Cover stale pans, rolling eviction/window bounds, same-tail corrections, equal timestamps, state timelines, earlier-endpoint resets, and feedless detail history.
- Visual/animation/reference parity is outside this bounded repair. Do not use these scheduling results to mark broader Module 09 complete.

## Handoff

The bounded async rolling-revision repair is implemented, independently verified, and green after Module 07 anchor refresh, with the stale-viewport fallback above still open. It should be fixed before calling the daily PoC graph path performance-stable. Keep broader Module 09 unresearched/incomplete and return to the user's staged sequence: Module 08 research only is next. A later explicitly scoped Module 09 task may address coordinator provenance, chunked/ring rolling storage, or visual parity. Never infer viewport freshness or ancestry from a content hash, `contentRevision`, or endpoint timestamp.

## Change log

- 2026-07-20: Created bounded cache-warming/engine-benchmark packet.
- 2026-08-22: Refreshed stale native anchors and dependency graph for the async rolling-revision repair; documented the synchronous/background shared cache race, upstream publication boundary, direct-lineage contract, stale bypass oracle, and exact implementation handoff. Broader Module 09 remains unresearched.
- 2026-08-22: Pinned the implemented coordinator/feed/direct-lineage worktree, recorded independent deterministic, integration, release-build, and live actual-card verification, qualified feed losslessness by mounted subscription lifetime, and marked only the bounded repair implemented and verified.
- 2026-08-23: Recorded 1,897 safe but expensive stale-viewport alignment/full fallbacks, rejected and reverted content-hash/timestamp ordering shortcuts, and narrowed the sound follow-up to coordinator-owned accepted-input provenance. Broader Module 09 remains unresearched.
- 2026-08-31: pinned the extracted history/feed storage owner and current history-startup symbols, inspected seven advanced anchors, and regenerated a green 41-node / 241-edge graph. The bounded repair remains verified; the stale-viewport fallback and broader Module 09 remain open.
- 2026-09-01: inspected the three shared Module 06 anchors and regenerated a green 41-node / 241-edge graph with fingerprint `cb7d9ccb260785fef2e01d2209b707e0595264b46c2fcc439d7344b241b1e0e5`. Core Graphics remains primary; the stale-viewport fallback and broader Module 09 remain explicitly open.
- 2026-09-08: inspected the Module 07 shared state/presentation anchors and regenerated a green 41-node / 241-edge graph with fingerprint `04558a72c823b10a561fdd2ddbedc038be0f323c071655596d6f714589ba2658`. Core Graphics remains primary; the stale-viewport fallback and broader Module 09 remain explicitly open. Module 08 research only is next.
