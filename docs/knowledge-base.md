# Durable knowledge and assumptions

This file preserves non-obvious facts that are not reliably encoded in the
current source tree but materially affect NativeHA reasoning. Typical entries
include live Home Assistant data properties, measured local performance,
environment behavior, and assumptions that an agent initially got wrong and
later corrected through experiment or explicit user instruction.

This is not a substitute for source code, tests, product decisions in
`docs/user-deviations.md`, configuration contracts in `docs/configurability.md`,
or detailed benchmark reports. Keep entries concise and link to the durable
evidence.

## Maintenance rules

- Add or update an entry when a repeatable experiment, durable user correction,
  or completed investigation establishes or invalidates a non-obvious fact
  future agents are likely to get wrong or waste time rediscovering.
- State the claim, scope, evidence, and conditions that require revalidation.
  Distinguish measured facts from user-approved assumptions and hypotheses.
- Do not promote speculation, a single unexplained observation, transient bug
  state, or easily discoverable code behavior into this file.
- Treat measurements as local observations, not portable guarantees. Record the
  machine, data shape, configuration, date, and source artifact when available.
- When new evidence conflicts with an entry, update or retire it instead of
  silently working around it. Preserve a short explanation and link to the new
  evidence.

## Current live Home Assistant deployment

### SPS30 history timestamps are strictly increasing

- **Claim:** For the current deployment's `sensor.sps30_pm2_5` history, effective
  timestamps are assumed to arrive in strictly increasing order. Do not assume
  duplicate or out-of-order timestamps are the cause of an SPS30-specific bug
  without new evidence. Generic history code may still defend against broader
  Home Assistant inputs when its contract requires that behavior.
- **Status:** Deployment-scoped user-confirmed assumption, supported by tracked
  live captures and measurements.
- **Evidence:** A 2026-07-22 read-only scan of the tracked `Tests/Fixtures/History/sps30_1day.json`
  capture found 83,969 effective timestamps and zero adjacent pairs for which
  the later timestamp was less than or equal to the earlier timestamp.
  Separately, `Benchmarks/HistoryFetch/sps30_timestamp_check.py` fetched fourteen consecutive
  one-day history windows. `Benchmarks/HistoryFetch/sps30_timestamp_results.txt` records
  1,173,621 total timestamps, 1,173,621 unique timestamps, zero duplicated
  timestamp values, and zero points involved in duplicates. The fourteen-day
  persisted summary proves uniqueness but does not independently calculate
  ordering.
- **Revalidate when:** The SPS30 entity or integration, Home Assistant recorder,
  server deployment, history API path, or timestamp selection policy changes,
  or a captured response provides a counterexample.

## Local performance observations

### Direct typed history decoding materially reduced 12-hour load time

- **Claim:** On Joy's MBP (2), for the current four-entity CO2/VOC 12-hour
  replay, direct typed WebSocket event decoding plus numeric-timestamp graph
  projection reduced release live publication from 4.735 seconds to
  1.397–1.485 seconds. The server protocol was already fast enough that
  switching from `history/stream` to `history/history_during_period` was not the
  important optimization.
- **Status:** Implemented and measured local observation, not a portable timing
  guarantee.
- **Evidence:** `Benchmarks/HistoryFetch/results.md` records three equivalent
  Python protocol runs, pre/post release NativeHA live-smoke runs, and
  five-iteration Swift comparisons. The 4.94 MB/102,418-sample event took
  3.633 seconds through the retained generic/re-encode comparison path versus
  0.387 seconds through direct typed decoding. Numeric projection took 0.060
  seconds after the change versus 0.564 seconds before it.
- **Revalidate when:** WebSocket envelope routing, JSON representation,
  subscription delivery, history model/projection, server recorder behavior,
  entity cadence, compiler, OS, or hardware changes.

### Metal is materially faster for the measured graph workload

- **Claim:** On Joy's MBP (2), the 2026-07-25 release benchmark favored Metal for
  the measured four-series SPS30 graph workload at 496×178 points, 2× scale, and
  4× zoom even when Metal includes command completion, shared-texture readback,
  and production `CGImage` creation. Present-ready p50/p95 was 1.645/1.720 ms at
  `1h` and 4.174/4.614 ms at `24h` for Metal, versus 3.700/4.015 ms and
  10.405/12.828 ms for Core Graphics.
- **Status:** Measured local observation, not a cross-machine guarantee or a
  permanent implementation decision.
- **Evidence:** `Benchmarks/GraphRendering/results.md`, section “2026-07-25
  production-image benchmark correction,” using five measured
  consecutive rolling revisions after three warm-up frames and the same
  immutable live frame sequence for each engine.
- **Revalidate when:** Rendering algorithms, preparation/downsampling,
  scheduling, graph dimensions, scale, data density, hardware, OS, or compiler
  changes materially. Use the tracked benchmark rather than extrapolating these
  numbers to a different workload.

### Rolling 12-hour graph preparation previously saturated the main thread

- **Claim:** At commit `c8bda39`, the rolling-history render path performed work
  proportional to the complete retained window for every live revision,
  including synchronous main-thread prepared-series work. For the live CO2/VOC
  card at `12h`, each SPS30 series retained about 41,900 points and commonly
  spent about 40 ms in main-thread `incrementallyUpdate` per revision. This was
  a steady-state interaction-lag source after history loaded, separate from
  initial WebSocket fetch/typed decoding and independent of render engine.
- **Status:** Reproduced and diagnosed on 2026-08-22, then repaired in the
  current bounded Module 09 worktree. `GraphChartRenderCoordinator` is now the
  single per-chart preparation/render owner; accepted publications are fed FIFO
  while the chart observer is mounted, obsolete visual frames coalesce, and
  expensive preparation/rendering runs off-main. Before subscription the feed
  retains/replays only the latest snapshot, which is safe because the new
  coordinator generation starts cold or uses the verified fallback. The
  synchronous main-thread bottleneck is repaired; retained-window preparation
  itself is not yet O(1).
- **Evidence:** The launch table
  `log_c8bda39_dirty_20260822_054150_A29CE603` in
  `~/Library/Caches/NativeHA_Logs.sqlite` records the switch to `12h`, roughly
  41,875 SPS30 points per series, repeated 40–42 ms main-thread incremental
  preparations, parallel background preparation, and frequent background
  `could not align prefix` full-preparation fallbacks. An older 2026-08-20
  launch of the same commit recorded much worse transient values (hundreds of
  milliseconds on the main thread and up to seconds in background full
  preparation), showing that machine state amplifies the same app flaw. A
  five-sample release `GraphEngineBenchmarks` run with the actual CO2/VOC card
  entities measured 24-hour present-ready p50 of 94–101 ms across Metal, Core
  Graphics, and Canvas, of which 93–97 ms was preparation and only 1–3 ms was
  renderer work. A current live HA protocol comparison returned 101,946–101,965
  samples / 4.63–4.64 MiB for the 12-hour card, essentially the same shape as
  the tracked 2026-07-28 baseline of 102,437–102,453 samples / 4.71 MiB.
- **Repair verification:** Focused graph coordinator/cache regressions, history
  integration, the release app build, and the read-only live benchmark using
  the actual configured graph-card entities passed. The live 24h Core Graphics
  preparation stage remains about 95 ms on this machine, but it is now
  serialized off-main rather than freezing interaction. The bounded Module 09
  evidence packet pins the exact implementation/test anchors and lifecycle
  qualification.
- **Revalidate when:** Projection publication granularity, prepared-series
  caching/lineage, rolling-window storage, synchronous rendering, live entity
  cadence, or retained time range changes. Renderer-only improvements should
  not be expected to fix this preparation bottleneck.

### Graph revision hashes and endpoint timestamps do not establish ordering

- **Claim:** `HAHistorySeries.contentRevision` is a deterministic content
  digest, not a monotonic sequence, so numeric comparison cannot decide which
  snapshot is newer. Likewise, `firstTimestamp`/`lastTimestamp` describe
  payload boundaries rather than ancestry: corrections, removals,
  equal-timestamp changes, rolling eviction, and state timelines can invalidate
  an endpoint-based ordering assumption.
- **Status:** Confirmed during independent verification on 2026-08-23. Two
  attempted cache shortcuts were rejected and reverted. Numeric digest ordering
  returned stale values in existing same-shape and rolling-tail correctness
  tests; endpoint ordering was unsafe for corrections and feedless detail
  graphs even though it would likely suppress the common stale-pan fallback.
- **Use instead:** Establish ordering through coordinator-owned generation and
  accepted-revision provenance or exact projection lineage. A prepared-series
  cache lookup must not return a different fingerprint merely because its hash
  or endpoint appears numerically newer.
- **Revalidate when:** History revisions gain an explicit monotonic owner-local
  ordinal or the coordinator/render request contract changes to carry exact
  accepted-input provenance.
