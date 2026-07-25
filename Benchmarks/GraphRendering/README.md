# Graph rendering benchmarks

This XCTest benchmark target covers deterministic graph correctness/scheduling,
the existing Core Graphics live instrumentation, and a symmetric comparison of
Metal, Core Graphics, and Canvas.

## Three-engine latency benchmark

Run the authorized read-only live comparison in release mode:

```sh
NATIVEHA_LIVE_GRAPH_BENCHMARK=1 \
NATIVEHA_GRAPH_BENCH_ITERATIONS=20 \
swift test -c release --filter GraphEngineBenchmarks
```

The benchmark fetches the configured four SPS30 entities once for each `1h`
and `24h` window. It derives one identical sequence of constant-count rolling
revisions for all engines, with immediate-predecessor cache lineage, and uses
the same 496×178-point viewport, 2× scale, 4× zoom, deterministic pan sequence,
three warm-up frames, and measured iteration count in every case. The prepared
cache is reset between pure-render and present-ready phases and between engines.
Assertions require the expected initial full preparations followed entirely by
incremental preparations, every requested frame ID to complete, and every
renderer to produce nonempty work/output.

The benchmark injects the engine explicitly. It does not mutate
`AppConfig.graphRenderEngine`.

### Pure-render timer

The input is an already prepared and downsampled `GraphRenderResult`. Timing
starts immediately before actual engine work and stops at:

- Core Graphics: completed bitmap allocation/drawing and `CGImage` snapshot;
- Canvas: the production `GraphCanvasPlot` has completed a forced offscreen
  `NSHostingView.cacheDisplay` bitmap pass;
- Metal: production vertex/buffer construction, offscreen command completion,
  shared-texture readback, and `CGImage` creation have completed.

This retains the purpose of the old renderer-only comparison while replacing
its unused Canvas path and Metal buffer simulations with observable completed
renderer output. It excludes cache lookup/parsing, incremental preparation,
visible-range selection, downsampling/axis work, logical dispatch, and macOS
compositor presentation.

### Present-ready timer

Timing starts immediately before the next logical rolling frame is submitted
to a user-initiated worker. It stops only after that same frame has completed:

1. prepared-series cache access and full/incremental parsing;
2. visible-range selection, min/max downsampling, axes, and viewport geometry;
3. engine-specific path/vertex construction and renderer dispatch; and
4. the same Core Graphics image, Canvas offscreen bitmap, or Metal-backed
   `CGImage` boundary used by the pure-render timer.

For Core Graphics and Metal, `GraphBitmapRenderer.render` already returns the
presentation image. The present-ready timer validates that returned artifact
without invoking either renderer a second time. Canvas still needs the
offscreen SwiftUI harness because its renderer consumes prepared geometry.

This endpoint is named **present-ready**. It includes dispatch and completion
waiting inside NativeHA, but excludes Home Assistant network fetch, benchmark
harness setup, warm-up frames, macOS compositor scheduling, display scanout,
and physical screen presentation.

The optional stage report gives p50 values for prepared-series work,
downsampling/viewport geometry, engine renderer work, and residual
scheduling/waiting. Total present-ready latency is timed externally and remains
authoritative; it is not reconstructed by adding stage timers.

Both pure-render and present-ready reports include sample count, p50, p95, and
maximum. There are no machine-specific performance pass/fail thresholds.

Environment overrides:

- `HA_BASE_URL` and `HA_TOKEN` override `AppConfig`'s configured local server
  endpoints and token file.
- `NATIVEHA_GRAPH_BENCH_ITERATIONS` changes the measured sample count (minimum
  five; default twenty).
- `NATIVEHA_GRAPH_BENCH_ENTITY_IDS` accepts a comma-separated four-entity list.

No raw live history or credentials are stored by the benchmark.

## Other graph benchmark tests

Run deterministic pipeline, min/max oracle, and scheduler cadence checks:

```sh
swift test -c release --filter GraphRenderingBenchmarkTests
```

Run the older Core Graphics cold/warm 1×/2× live instrumentation when needed:

```sh
NATIVEHA_LIVE_GRAPH_BENCHMARK=1 \
swift test -c release --filter GraphRenderingLiveBenchmarkTests
```

That path records series preparation/cache lookup, viewport/downsampling/axis
work, bitmap allocation, context/background setup, path construction,
Core Graphics stroke/rasterization, and image snapshot time. It now selects
Core Graphics explicitly and resolves credentials/endpoints through
`AppConfig` or the environment rather than duplicating machine paths.

Record observed machine/build/data metadata and distributions in
[`results.md`](results.md). Results are reproducible observations, not portable
latency guarantees.
