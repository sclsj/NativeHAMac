# Graph freezes during zoom and pan — 2026-09-30

## Findings

The reported failure is reproducible. Three interacting defects were established; the inspected offending logic predates the recent climate and Markdown modules. This is a scoped diagnosis and repair, not a claim that every intervening module has been independently performance-audited.

1. **The mounted chart submitted the previous view's inputs.** On this macOS 12.6.7/Swift 5.6.1 machine, `onChange(of: token)` could invoke the previous view's closure. Ignoring its new value submitted the previous history, zoom and pan. The first update could produce no frame, and later updates lagged one revision. It also sent older history back through the prepared cache after accepted FIFO preparation had advanced. The mounted production-chart regression failed with seven assertions before the repair and passes afterward at both 1h and 12h.
2. **The coordinator starved a continuous gesture.** It discarded every completed frame unless its request sequence still equaled the newest requested sequence. A controlled 12 ms renderer with 2 ms input arrivals delivered zero frames during 150 requests over 300 ms, then one frame when input stopped. The repaired coordinator delivers completed frames in sequence within the current generation, coalesces pending viewports and reaches the final request. A representative release run delivered 20 frames during input and 22 overall. Owner/range/reset rejection tests remain passing.
3. **One filtered raw sample disabled fast history preparation.** The numeric fast path required a one-to-one raw-to-prepared point mapping. A read-only live 12h REST capture found 41,819 samples per SPS30 series and one `unavailable` state per series at approximately `2026-09-30T02:41:24Z`. This forced retained-window validation on every revision. After repairing the first two defects, live 12h logs still measured approximately 52–56 ms per SPS30 preparation, with about 96 ms of queue delay ahead of some frames. Tracking omitted source positions permits exact trusted-overlap reuse without changing the existing treatment of nonnumeric samples.

`b5c5532` (2026-08-22) already contains the same captured-token callback pattern and strict newest-request delivery condition. Its one-to-one numeric lineage guard also excludes filtered sources. These observations explain regressions that can appear at 1h as well as 12h, and a data-dependent worsening after an unavailable state enters the retained window. They do not attribute the failure to a recent module solely by timing.

## Evidence

- User session: `log_64a0c33_clean_20260930_075208_CAF9886F` in `~/Library/Caches/NativeHA_Logs.sqlite`. A read-only snapshot of its first 19,830 entries covered about 795 seconds and contained 2,430 prefix-alignment failures and 795 zoom/pan events. SPS30 full preparation p50 was about 52 ms per series; incremental preparation p50 was about 53–58 ms. Outliers reached hundreds of milliseconds or seconds. These are debug-build observations, not release performance guarantees.
- Process sampling: `/tmp/nativeha-before.sample.txt` showed background coordinator preparation and full rebuilding; it did not re-establish the old synchronous main-thread preparation flaw. `/tmp/nativeha-after.sample.txt` showed substantial SwiftUI main-thread work too. Eliminating graph waste does not prove that every possible UI hitch is gone.
- `GraphResponsivenessTests`: mounted production chart with rolling 3,600/43,200-point histories, current zoom/data assertions, continuous-input progress, stale queued-history rejection and a dense filtered-history cold oracle.
- `GraphRenderingTests.testExactLineageRetainsNumericIndexMappingAcrossUnavailableSamples`: rolling eviction and fresh unavailable samples match independent full preparation. Before repair it took four alignment fallbacks and zero exact-lineage updates; afterward it takes four exact-lineage updates and zero fallbacks.
- The 43,200-point filtered-history regression measured warm preparation median 0.349 ms in debug and 0.295 ms in release in representative runs; cold preparation was 22.194/7.157 ms respectively. Complete prepared points match the cold oracle. This measurement excludes fixture construction and does not claim end-to-end UI latency or O(1) storage copying.

## Repair and validation

The chart's equatable change value now carries the current request and feed into the callback. The coordinator keeps FIFO accepted preparation, prevents an older queued snapshot from rewinding it, and allows ordered completed-frame progress during a continuous gesture. Numeric preparation maintains a sparse list of omitted raw indices and translates trusted source overlap into prepared-point overlap. Duplicate/out-of-order numeric timestamps, changed overlap, unsupported lineage and owner generations retain their correctness safeguards. Sampling, renderer, graph precision and approved product behavior are unchanged.

Debug frame diagnostics report response, queue and render times, plus delivery/rejection. Their metadata and timing compile out in release.

Validation completed:

- 59 focused debug tests: graph rendering/responsiveness, history integration and settled graph PNG rendering.
- 35 focused release tests: graph rendering/responsiveness and release logging erasure; release app linked successfully.
- The generated settled graph PNG was inspected. This repair does not establish the deferred step-end, hover or smooth y-axis parity work.

Live 1h and 12h history loading and updates were exercised. A later native-handler probe in the normal debug executable (`log_64a0c33_dirty_20260930_114059_9D84A242`) sent 120 zoom and 120 pan events directly through the existing `TrackingView.scrollWheel` handler at 1h. It delivered 263 zoomed-chart frames during that input interval. Frame response p50/p95/max was 39.7/130.2/264.7 ms; queue delay p50/p95 was 0.53/4.51 ms and render time p50/p95 was 8.61/19.29 ms. The requested 120 Hz timer took 17.9 seconds to process all 240 inputs, so this proves progress but does not establish smooth physical trackpad throughput. Significant main-thread scheduling/delivery delay remains a measured limitation of this debug session.

Desktop gesture injection was affected by focus/launch state and concurrent computer use; macOS later reported `loginwindow` as the foreground process. A temporary bundle also failed token-file access and was discarded as a live-test setup. Do not interpret an attempted injection without matching interaction logs as a passing gesture check. Physical trackpad acceptance remains a user check after the normal final build is launched. `GraphFrame` diagnostics distinguish any remaining preparation, drawing and main-thread delivery stalls.

## Next check

Use the final debug build and repeat the user's ordinary trackpad zoom/pan at 1h and 12h. If a freeze remains, retain that session and correlate its interaction timestamps with `GraphFrame` response/queue/render timing. Investigate the demonstrated remaining path rather than reverting unrelated modules.
