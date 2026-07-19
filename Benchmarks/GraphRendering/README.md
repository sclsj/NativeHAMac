# Graph rendering benchmark

This target measures the production `GraphBitmapRenderer` and viewport
scheduler used by `BitmapLineChart`. It exists to keep the gesture-starvation
decision reproducible rather than relying on a generic drawing microbenchmark.

The deterministic cases run with the normal test suite and verify two things:

- the Accelerate min/max implementation exactly matches a scalar min/max
  oracle on smooth, noisy, and adversarial spike data;
- 8 ms viewport events with a 20 ms renderer produce intermediate frames,
  keep only one render in flight, and settle on the newest token;
- a production-shaped four-entity/100,000-point rolling stream carries 20
  append/trim updates through accumulator, publication coalescing, projection,
  prepared-series construction, and min/max sampling. Four updates are
  intentionally coalesced into each delivery. The benchmark requires exact
  equality with a cold projection oracle, zero normal-traffic resets/full
  accumulator fallbacks, and one incremental projection/preparation per entity
  and delivered update after the initial cold build.

The live case fetches the four SPS30 particulate sensors from Home Assistant
over the existing read-only REST benchmark path for both `1h` and `24h`. For
each window it records decoded data size, point count, cold preparation, and
warm panning at 496×178 points and 1×/2× scale. Production instrumentation
separates series preparation/cache lookup, viewport range/min-max/axis work,
RGBA allocation, context/background setup, path construction, CoreGraphics
stroke/rasterization, and image snapshot time. The 1× and 2× cases must retain
identical sampled points, axes, and visible bounds.

Run the deterministic benchmark tests:

```sh
swift test -c release --filter GraphRenderingBenchmarkTests
```

Run the authorized read-only live benchmark:

```sh
NATIVEHA_LIVE_GRAPH_BENCHMARK=1 \
  swift test -c release --filter GraphRenderingLiveBenchmarkTests
```

Optional environment variables:

- `HA_BASE_URL` and `HA_TOKEN` override the configured local endpoints/token
  file.
- `NATIVEHA_GRAPH_BENCH_ITERATIONS` changes the default 30 warm renders per
  scale and time window.
- `NATIVEHA_GRAPH_BENCH_ENTITY_IDS` accepts a comma-separated sensor list.

The live run does not store credentials or raw multi-megabyte history. Record
machine-specific observations and the printed data-size metadata in
[`results.md`](results.md). Timings are medians/p95 observations, not portable
performance limits.
