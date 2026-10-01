# Independent verification of the graph responsiveness repair — 2026-10-01

Reviewed repair `5158912` and subsequent user-confirmation record `705b10c`, against parent `64a0c33`, using the verification route. This review made no graph application or test changes. Existing climate work in the shared tree is outside this review.

## Verdict

The three targeted repairs are supported by the focused deterministic checks: mounted charts consume current inputs, completed frames make progress during continuing input, and filtered history retains exact predecessor reuse while matching cold preparation. This does not establish that all graph freezes are fixed. Static review found a new starvation case when the member list of an already-mounted unit group changes without changing its history feed. The reported user improvement remains valid evidence for the interaction they exercised.

## Findings

### P2 — Changed group membership can reject every subsequent frame

The new equality gate in `Sources/NativeHAMac/GraphRenderScheduling.swift:424` compares the entire accepted input list with the visual input list. However, `GraphChartMountedLifecycle.connect` returns immediately when the feed UUID is unchanged (`:67`), and its observer permanently captures the initial input templates (`:77`).

A reachable sequence is:

1. A configured card requests sensors A and B with the same unit, but its initial history publication contains only A. The unit chart mounts with A's input template.
2. A later normal publication introduces B. The accumulator explicitly permits newly introduced entities in `Sources/NativeHACore/HomeAssistantHistoryStream.swift:216`; projection only includes entities present in history. No feed replacement is necessary.
3. `HistoryGraphCard` groups the new projected history by current unit and retains its `ForEach` identity for the existing unit (`Sources/NativeHAMac/CardViews.swift:577`, `:635`). Its visual request now contains A and B.
4. The existing feed observer still submits only A. Calling `connect` with A and B does nothing because the feed UUID matches. For example, accepted identities `[(scope, A, revision 2, count 100)]` cannot equal visual identities `[(scope, A, revision 2, count 100), (scope, B, revision 1, count 1)]`. This remains unequal on every later publication and gesture. The graph retains its old image until it is remounted or its feed changes.

A current-state unit change that moves a sensor into an existing group has the same structural problem. The stale template capture predates this repair; permanently rejecting the expanded group's visual requests is introduced by the new equality gate. This finding is established by the execution paths above, **not by a new mounted runtime reproduction**. The passing mounted regression uses a fixed single-entity member list and does not cover this transition.

Smallest corrective direction: treat changes to a mounted group's input membership/cache identity as a subscription-template transition, refreshing the observer and replaying the current accepted snapshot before requesting its visual. Retain the stale-history rejection and generation safeguards. Add a mounted late-second-entity regression when graph test changes are authorized.

### Benchmark harness limitations

- The default live engine benchmark currently receives only one point for two of its four default series. On this run its `>23` assertion at `Benchmarks/GraphRendering/GraphEngineBenchmarks.swift:282` failed twice, then unchecked rolling slicing (`:303`) terminated the process with signal 5. No live timing was emitted. A later read-only `/api/states` check showed the default `sensor.sps30_pm4_0` and `sensor.sps30_pm10` identifiers absent. This is a benchmark input/harness failure, not an application performance result.
- The benchmark's exact-lineage expectation still requires every raw row to be numeric (`:259`). The repair deliberately allows omitted rows. The later actual-card rerun reproduced this outdated oracle at 24h: each engine/phase produced four full preparations, 88 incremental preparations, **88 exact-lineage updates and zero alignment fallbacks**, while the oracle expected zero exact-lineage updates and 88 fallbacks. This caused six assertion failures. The new filtered-history tests cover that changed contract; the tracked benchmark oracle was not updated by this repair.
- The older cold/warm live benchmark creates inputs without a fixed `windowEnd` (`Benchmarks/GraphRendering/GraphRenderingBenchmarks.swift:393`), so each render obtains a different `Date()` endpoint in `GraphRendering.swift:323`. Its exact 1×/2× x-tick and viewport-bound equality checks failed three times per window, six assertions total. Sample points and y-axis comparisons passed. Its unconditional `GRAPH_FIDELITY ... equal=yes` line is misleading and must not be treated as passing fidelity validation. This endpoint issue predates the repair.

## Fresh checks

Environment: Joy's MBP (2), macOS 12.6.7, Swift 5.6.1/Xcode 13.4.1. Runs used the existing test sources and did not send HA service calls.

- `swift test --filter 'GraphResponsivenessTests|GraphRenderingTests|GraphRenderSchedulingTests|HistoryIntegrationTests'`: **34 executed tests passed**. The latter two names match no separate suites; the actual executed suites were `GraphRenderingTests` and `GraphResponsivenessTests`.
- `swift test --filter 'HistoryStreamIntegrationTests|GUIRenderingAndPerformanceTests.testHistoryGraphViewCanRenderToPNG|GUIRenderingAndPerformanceTests.testWarmGraphInteractionRenderCanBeMeasuredWithXCTMetrics'`: **26 executed tests passed**, including 24 history integration tests.
- The mounted 1h and 12h regressions each delivered four frames, with one full preparation, three exact-lineage updates, and zero alignment fallbacks. The 300 ms continuous-input test requested 150 viewports and delivered 20 frames during input, 22 overall, reaching the last requested viewport.
- The 43,200-point filtered fixture matched all prepared points against the cold oracle. Debug warm median preparation was **0.409 ms**, versus **22.844 ms** for the cold oracle. These are preparation measurements, not event-to-screen latency.
- The existing warm interaction XCTest measured approximately **3.76 ms wall time**, **4.07 ms CPU time**, and **1,043 kB physical-memory change** on average over three samples. Memory variation was high (67% relative standard deviation); there is no accepted performance baseline. These synthetic fixture metrics are not live 24h resource measurements.
- The settled `.build/render-artifacts/history-graph.png` was opened and inspected: the graph line, grid, unit and tick labels rendered. It was not compared against a fresh matched HA browser capture, and it is not evidence of animation or step-end parity.
- The release app and test bundle built successfully. The combined release/live command then failed in the first default engine benchmark as described above; suites scheduled after that crash must not be counted as executed.

Raw local outputs: `/tmp/nativeha-graph-review-debug.log`, `/tmp/nativeha-graph-review-integration.log`, `/tmp/nativeha-graph-review-release.log`. The failed default release command's process CPU/RSS includes compilation and cannot be used as a graph CPU/memory result.

## Live rerun with configured card entities

The benchmark supports an entity-list override. The rerun used the four CO2/VOC card entities already recorded in `Benchmarks/HistoryFetch/results.md`: `sensor.qtpy_air_quality_bme688_iaq`, `sensor.qtpy_air_quality_scd41_co2`, `sensor.sps30_pm2_5`, and `sensor.sps30_pm1_0`. Read-only live checks confirmed dense data for the current entities. This is a mixed-sensor workload, not the default four-SPS30 benchmark. Its common single-unit benchmark viewport also does not reproduce the dashboard's separate unit groups.

Command:

```sh
NATIVEHA_LIVE_GRAPH_BENCHMARK=1 \
NATIVEHA_GRAPH_BENCH_ITERATIONS=20 \
NATIVEHA_GRAPH_BENCH_ENTITY_IDS=sensor.qtpy_air_quality_bme688_iaq,sensor.qtpy_air_quality_scd41_co2,sensor.sps30_pm2_5,sensor.sps30_pm1_0 \
/usr/bin/time -l swift test -c release --skip-build \
  --filter 'GraphEngineBenchmarks|GraphRenderingLiveBenchmarkTests|GraphRenderingBenchmarkTests|GraphResponsivenessTests'
```

The already-built release binary was used, isolating this graph check from subsequent climate source edits. **Nine tests executed: seven passed and two failed with the 12 harness assertions described above.** The command exited 1. Three deterministic pipeline/min-max/scheduler benchmarks and all four responsiveness tests passed. The two live benchmarks completed measurements but are not green acceptance gates.

The engine benchmark fetched 8,560 points at 1h and 204,355 at 24h. Each phase used three warm-up frames and 20 measured rolling revisions at 496×178 points, 2× scale, 4× zoom. Present-ready timing excludes HA fetch and compositor/display latency.

| Window | Engine | Present-ready p50 / p95 / max (ms) | Preparation p50 (ms) |
|---|---|---:|---:|
| 1h | Core Graphics (production default) | 1.478 / 1.735 / 1.755 | 0.216 |
| 24h | Core Graphics | 7.234 / 7.728 / 7.995 | 3.448 |
| 1h | Metal | 1.753 / 3.963 / 4.099 | 0.222 |
| 24h | Metal | 5.120 / 6.689 / 6.859 | 3.407 |
| 1h | Canvas | 1.605 / 1.903 / 8.229 | 0.223 |
| 24h | Canvas | 7.568 / 8.071 / 8.369 | 3.350 |

The separate Core Graphics cold/warm test fetched 8,566/204,350 points. At 2× scale, cold totals were **7.311 ms (1h)** and **146.157 ms (24h)**; unchanged-history warm p50/p95 were **1.195/1.401 ms** and **3.717/4.382 ms**. Rolling preparation and unchanged-history cache hits are different workloads; their timings should not be conflated.

The complete skip-build process took 22.92 s wall, 8.72 s user CPU, 0.82 s system CPU, with maximum RSS **840,499,200 bytes (about 802 MiB)**. This includes SwiftPM/test harness overhead, live response decoding, retained 23-frame sequences, all engines and tests. It is not a per-frame or app steady-state resource figure, and no comparative memory baseline was established.

Release filtered-history preparation matched the cold oracle with warm median **0.362 ms**, cold **7.689 ms**. Release continuous input delivered 20 frames during 144 requested viewports, 22 overall; mounted 1h/12h checks again passed. Full local output is `/tmp/nativeha-graph-review-live-card.log`.

## Scope and remaining checks

The expected numeric-hover failure remains explicitly expected. The existing step-end pixel test passes but retains its documented false-positive limitation. Reference source still uses step-end series and null gaps; this repair preserves NativeHA's prior filtered output and does not close those pre-existing graph semantics gaps or the approved smooth y-axis work.

This review did not newly exercise physical trackpad inertia, simultaneous unrelated controls/dismissal during dense live preparation, or sustained compositor latency. The prior user's smoothness confirmation is not a new measurement by this reviewer. The next graph change should reproduce and repair the membership transition while retaining the passing responsiveness and filtered-history regressions. Complete acceptance also needs the benchmark's filtered-lineage oracle and fixed-time cold/warm comparison repaired and rerun, plus the remaining interaction checks. No rendering fidelity reduction was introduced by the reviewed diff, but the pre-existing parity gaps and failing benchmark assertions prevent a blanket conformance claim.
