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
- **Evidence:** A 2026-07-22 read-only scan of the tracked `sps30_1day.json`
  capture found 83,969 effective timestamps and zero adjacent pairs for which
  the later timestamp was less than or equal to the earlier timestamp.
  Separately, `Benchmarks/sps30_timestamp_check.py` fetched fourteen consecutive
  one-day history windows. `Benchmarks/sps30_timestamp_results.txt` records
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
