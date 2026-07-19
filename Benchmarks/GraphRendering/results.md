# Recorded graph-rendering results

## 2026-07-19 settled 12h append/coalescing repair

The new deterministic end-to-end case models four numeric entities with
25,000 points each, then twenty five-point-per-entity rolling updates. It
delivers every fourth update so the measured path includes accumulator work,
publication coalescing, compact projection, prepared numeric series, and
min/max sampling instead of timing those stages in isolation.

At `bbe0768`, every group of normal append publications collapsed to a reset.
That caused 24 full entity projections and 24 full prepared-series builds. The
single baseline release run measured 56.125 ms in accumulation, 3,179.182 ms
in projection, and 677.397 ms in preparation/min-max work: 3,912.705 ms total.

The repaired path composes the exact intersection of consecutive snapshot
lineages, mutates uniquely owned rolling arrays in place, retains copy-on-write
snapshot safety when a callback is still using an older array, and does not
retain the prior compact window in the projection cache. The three final
release runs had a 714.208 ms median total (24.700 ms accumulation, 566.287 ms
projection, 120.439 ms preparation/min-max), a 5.48× end-to-end improvement
over the captured baseline. Every run reported:

- zero coalesced resets and zero accumulator full fallbacks;
- 80 reusable entity paths across the twenty updates;
- four initial full plus twenty incremental entity projections;
- four initial full plus twenty incremental prepared-series builds;
- exact final projected points against the cold full oracle.

The same release verification kept all correction, out-of-order, missing-
lineage, reconnect-generation, and unsorted/gapped retained-input fixtures on
their conservative full paths. The 100×200 out-of-order history benchmark
remains exact; the release `HistoryStreamBench` result improved from the prior
89.480 ms recorded at `bbe0768` to 47.714 ms while retaining checksum
`8026277772552279935`.

## 2026-07-19 rolling-history CPU repair and live GUI verification

After the receive-limit repair made 12h reliable, a release-app profiler found
the remaining settled 12h load was not bitmap rasterization or WebSocket
decode. Six history owners repeatedly rebuilt every projected timestamp with
Foundation, and same-count rolling windows forced full prepared-series cache
rebuilds. The final repair makes overlap provenance event-driven: the history
accumulator classifies reset, unchanged, normal append/trim, and out-of-order
reset while it already merges and trims, and publishes retained old/new indices
with normal updates. `HAHistoryProjectionStore` therefore formats only the
moving boundary/tail without performing a routine O(n) equality scan. It
attaches predecessor/index lineage to projected series; the graph cache checks
that lineage against its cached revision in O(1), freshly prepares a moved
boundary and new tail, and reuses only the trusted numeric overlap. Raw/manual,
corrected, reset, and out-of-order publications rebuild fully. Monotonic owner
generations reject stale callbacks and prevent reconnect/refresh cache bridges.

The deterministic 100,000-point oracle remained exactly equal. In the final
release run, incremental projection took 3.542 ms versus 592.864 ms for the
full oracle. The normal full-suite debug run measured 19.218 ms versus
924.713 ms. Same-shape middle replacement tests prove both projection and
prepared-series caches rebuild fully rather than hiding a correction.
A combined rolling-window middle correction plus newer tail deterministically
renders `[20, 99, 40, 50]` through the full path; the unchanged clean rolling
fixture still records one full and one incremental preparation.
The actual 99,999-point moved-cutoff/unchanged-overlap/one-tail fixture exactly
matches a cold full oracle, retains its new boundary, and records one full plus
one incremental graph preparation. Final debug graph preparation measured
10.069 ms incremental versus 274.580 ms cold full; release measured 1.523 ms
versus 115.503 ms. Neither projection nor graph preparation performs a routine
O(n) history equality scan on a normal tail.

A fresh verifier then supplied an adversarial reference-compatible shape:
existing history `[10:X, 30:A, 20:B, 40:C]`, cutoff 25, and an incoming
duplicate `[40:C]`. Because the incoming first timestamp is not older than the
existing last timestamp, the reference does not sort and produces
`[25:B, 30:A, 40:C, 40:C]`. The accumulator now emits overlap only when the
retained existing indices form one exact contiguous suffix; this case carries
no lineage and records two full projections plus two full graph preparations,
both exactly equal to cold oracles. The proof is counted inside the existing
cutoff filter pass and adds no full-window scan.

An independent release GUI run then loaded the exact CO2/VOC 12h owner in six
seconds, observed 80/80 `Live` samples over 36 seconds with no reconnect, and
measured settled CPU samples averaging 26.43%, down 77.5% from the reproduced
117.7% pre-repair condition. With the optional plot-only overlay disabled,
17/17 SPS30 gesture frames were unique and the last two settled frames had the
same SHA-256. Returning to 1h rendered by the second capture, remained `Live`
for 60/60 samples over 25 seconds, and left no app process running. No
publication cadence, accepted-sample ordering, merge, deduplication, or wire
semantics changed.

## 2026-07-19 validated timestamp fast path

After replacing the provisional timestamp parser with fully validated UTC,
fractional-second, and explicit-offset handling, a five-iteration read-only
release smoke retained exact 1×/2× points, axes, and visible bounds. The live
input contained 13,988 points at 1h and 335,700 points at 24h. Cold preparation
dropped from the 2026-07-18 Foundation-dominated observations below to
23.6/23.7 ms at 1h and 747.5/571.6 ms at 24h for 1×/2× respectively. Warm
viewport rendering remained a separate CoreGraphics-dominated cost; this short
five-sample run is correctness/performance-smoke evidence rather than a new
portable latency baseline.

The companion parser matrix covers canonical UTC, fractional seconds, positive
and negative offsets, calendar/clock/offset validation, trailing input, and a
20,000-point hot-path measurement. The fallback formatters are shared and used
only for noncanonical ISO-8601 shapes, avoiding formatter construction during
normal SwiftUI body recomputation.

## 2026-07-18 local development machine

Commands:

```sh
swift test -c release --filter GraphRenderingBenchmarkTests
NATIVEHA_LIVE_GRAPH_BENCHMARK=1 \
  swift test -c release --filter GraphRenderingLiveBenchmarkTests
```

The read-only live run used four SPS30 series at 496×178 points with production
min/max sampling and 30 warm pan positions per case.

| window | series | live points | decoded JSON bytes | fetch |
|---|---:|---:|---:|---:|
| 1h | 4 | 13,976 | 1,103,692 | 255.723 ms |
| 24h | 4 | 335,776 | 26,490,281 | 5,090.231 ms |

Cold rendering is dominated by string timestamp parsing/prepared-series cache
construction, not bitmap work. The 1h cases draw 884 min/max points and the
24h cases draw 888.

| window | scale | cold preparation | cold viewport | cold total | RGBA bytes |
|---|---:|---:|---:|---:|---:|
| 1h | 1× | 586.309 ms | 0.089 ms | 589.456 ms | 353,152 |
| 1h | 2× | 613.319 ms | 0.047 ms | 616.787 ms | 1,412,608 |
| 24h | 1× | 13,406.003 ms | 0.264 ms | 13,411.281 ms | 353,152 |
| 24h | 2× | 13,615.290 ms | 0.292 ms | 13,621.899 ms | 1,412,608 |

Warm interaction has cache-hit preparation below 0.04 ms. CoreGraphics
stroke/rasterization is the dominant stage and varies with path geometry.

| window | scale | total median | total p95 | viewport | allocation | path build | stroke/raster | snapshot |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1h | 1× | 2.566 ms | 3.698 ms | 0.038 ms | 0.053 ms | 0.047 ms | 2.348 ms | 0.033 ms |
| 1h | 2× | 3.555 ms | 5.360 ms | 0.041 ms | 0.190 ms | 0.049 ms | 3.144 ms | 0.037 ms |
| 24h | 1× | 5.787 ms | 8.963 ms | 0.272 ms | 0.046 ms | 0.047 ms | 5.305 ms | 0.030 ms |
| 24h | 2× | 7.047 ms | 10.540 ms | 0.278 ms | 0.184 ms | 0.050 ms | 6.371 ms | 0.041 ms |

For both live windows, 1× and 2× output retained identical min/max points,
axes, tick values, and visible bounds. The deterministic 100,000-point
smooth/noise/spike fixture also matched the scalar min/max oracle exactly.

### Candidate comparison

The pre-change live 12h candidate run contained 167,832 SPS30 points at
496×220 and 1×. Min/max sampling took 0.537 ms, axis work 0.004 ms, and
CoreGraphics path rendering 5.102 ms for a 5.599 ms pipeline. Immediate line
drawing was effectively tied at 5.052 ms, LTTB was slower at 6.556 ms, and
cached min/max changed the full pipeline by only about 0–6%. Stride reduced the
pipeline to 3.424 ms but can omit spikes, so it was rejected as the production
fidelity path. Disabling antialiasing was likewise rejected.

The live 1h full-resolution path is already comfortably below the 8 ms event
cadence once warm. The 24h p95 crosses that cadence, and no latency-only change
can guarantee publication when tokens arrive faster than renders. Therefore
the implementation keeps full-resolution min/max and fixes ownership instead
of selecting a lower-fidelity algorithm or a data-size crossover.

### Scheduler result

With 24 viewport events at 8 ms and an intentionally slower 20 ms renderer,
the strict old latest-token model publishes zero frames during the gesture.
The serialized/coalesced scheduler started 10 renders, completed 10, replaced
14 pending requests, published 8 frames before gesture end, never exceeded one
concurrent render, and settled on the final token. This removes the 100% frame
discard mode while bounding obsolete CPU work.

### Live 1h gesture capture

The release app was launched against the configured live server at `1h`. A
160-event pixel-scroll stream was posted to the SPS30 PM2.5/PM1.0 graph with an
8 ms requested interval; event-post overhead made the measured stream last
1.661 seconds. Twenty full-window frames were captured at 0.214–1.620 seconds,
all before the event stream ended. The fixed SPS30 plot crop had 15 distinct
signatures across those 20 in-gesture frames, and direct montage inspection
showed progressive x-window and line updates followed by the final settled
viewport. This confirms the live graph no longer discards every intermediate
frame during continuous scrolling.

Times are observations for this machine and live data, not portable limits.
