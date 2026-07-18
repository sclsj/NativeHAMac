# Recorded graph-rendering results

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
