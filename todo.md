# NativeHA Module 01 continuation handoff

Date: 2026-07-19. This is the authoritative final-orchestrator handoff after
Module 01 implementation, visual repairs, live SPS30 stress work, Gemini's
three follow-up commits, the contract-revision-2 transport/parser repair, the
rolling-history CPU repair, and fresh independent GUI verification. The packet
is now `complete` after fresh bounded independent verification; the
orchestrator only needs to commit the intentional settled tree. Do not re-audit
the frontend while its regenerated graph stays green.

## 2026-07-19 contract-revision-2 repair status

The confirmed 12h transport regression is repaired in the current working tree.
A typed `HomeAssistantWebSocketReceivePolicy` is applied to the concrete
URLSession WebSocket task before `resume`; normal library callers keep the
1 MiB platform default while `NativeHAMac` selects a finite 32 MiB per-message
cap. The cap covers the measured 26,490,281-byte 24h four-series SPS30 response
and is not eager allocation. The unsupported 120-second command timeout is
restored to 10 seconds.

Deterministic coverage now includes a production-adapter receive one byte above
the platform default and 64 concurrent commands plus 64 subscriptions and their
unsubscribes on a fake transport that rejects non-increasing actual wire IDs.
Both pass with zero final ownership. The timestamp fast path now validates UTC,
fractional seconds, positive/negative offsets, calendar/clock/offset bounds,
and trailing input; malformed canonical shapes cannot fall through to
Foundation normalization. Noncanonical fallback formatters are shared instead
of being constructed during SwiftUI recomputation.

The read-only release live smoke passed exact `CO2/VOC` 1h → 12h → 1h with the
production policy: 8,530 points / 0.495s; 102,565 points / four callbacks /
6.087s; 8,528 points / 0.470s. It observed zero reconnecting or non-ready states,
zero owner errors, and zero ownership after every window. Representative 24h
also passed with 56,470 points in 2.716s. The release SPS30 graph benchmark
retained exact 1x/2x points, axes, and bounds for 13,988 1h and 335,700 24h
points. Cold preparation was 23.6/23.7 ms at 1h and 747.5/571.6 ms at 24h.

The floating sample hover/crosshair overlay remains normally enabled and can be
disabled for repeatable captures without code edits using
`NATIVEHA_GRAPH_HOVER_OVERLAY=0`. This gates drawing only; scroll/zoom/pan input
remains installed and has focused policy/PNG coverage.

Current local deterministic results: WebSocket 19/19; combined history,
integration, graph, and GUI 32/32 (with the two pre-existing expected Module 09
parity markers); timestamp matrix/performance and focused configuration tests
green; release scheduler benchmark 2/2. The module graph is regenerated at 21
nodes / 143 edges with fingerprint
`7fd7546a2f9b860af39694f3a1449d1d0d8e21bab8609e82b31f7c77dc395675`,
checker green; resolver self-test passes 28 nodes / 59 edges with fingerprint
`ab069e007ec7bfe3e9fb3019c9c58563ba9294af47b2ddb4fdc8bce4ef0a1f1a`.
Final current-tree validation after the event-driven projection-lineage repair
passed 87 tests with two intentional live-gated skips and zero failures in
52.858 seconds; all five products built before that proof-only follow-up; the
release scheduler benchmark passed 2/2; and the 100,000-point exact rolling
projection measured 3.542 ms incremental versus 592.864 ms full in release.
Preserve the
pre-existing untracked `sample.txt`.

Fresh independent release GUI verification passed: 12h CO2/VOC rendered by the
sixth capture, stayed `Live` for 80/80 samples over 36 seconds, and settled at
26.43% mean CPU versus the reproduced 117.7% before the exact-overlap repair.
All 17 SPS30 gesture captures were distinct with matching final two settled
hashes. Return to 1h rendered by the second capture and stayed `Live` for 60/60
samples over 25 seconds. The verifier terminated the app and confirmed no PID
remained. Exact final transport ownership is separately proven by the live
harness because the GUI exposes no ownership counter.

The final bounded reviews found both a prepared-series safety gap and an
over-strict common-path regression. The completed design is event-driven:
`HAHistoryStreamAccumulator` classifies reset, unchanged, normal append/trim,
and rare out-of-order reset while it merges, then publishes retained old/new
indices only when retained existing indices form one contiguous suffix. A
gapped retained entity projects fully. `HAHistoryProjectionStore` no longer performs a routine O(n) compact
equality scan. It attaches predecessor/index lineage; the graph cache checks
the predecessor in O(1), freshly prepares boundary/tail, and reuses only the
trusted one-to-one numeric slice. Raw/corrected/reset series rebuild fully.
Typed publications carry monotonic owner generation, so reconnect/refresh
cannot bridge caches and stale callbacks return nil without mutation. Transient
lineage is excluded from Codable output.

The correction plus newer tail renders `[20, 99, 40, 50]` through two full
preparations and zero incremental preparations. The actual 99,999-point moved
synthetic cutoff + unchanged overlap + one-tail fixture exactly matches cold
full output, contains its new boundary, and records full=1/incremental=1.
Release graph preparation is 1.523 ms versus 115.503 ms cold full (debug 10.069
vs 274.580 ms). No-lineage and reset-generation fixtures rebuild fully.
Focused graph 17/17, history 17/17, history-performance 6/6, and integration
3/3 pass.

## 2026-07-19 pre-repair cause snapshot (now resolved)

Gemini's work is already committed as `e4eecb2` (wire-ID registration/send
ordering plus a 120-second command timeout), `f8f55f0` (serialized/coalesced
viewport scheduler), and `3cd05d5` (timestamp fast path and formatter hoist).
The only pre-existing untracked file at this refresh is `sample.txt`; do not
modify or commit it as part of Module 01.

The 12h failure is now confirmed at the production adapter boundary. The exact
visible CO2/VOC `history/stream` replay is about 4,912,600 bytes / 102,618
points. `URLSessionWebSocketTask.maximumMessageSize` defaults to 1,048,576
bytes, and `URLSessionHomeAssistantWebSocketTransport` does not configure it.
The same card's 1h replay is about 406 KB and succeeds. A clean current-HEAD app
reproduces 12h `Loading history` plus Live/Reconnecting. The subscription
acknowledgement measured about 7 ms, so the 120-second command timeout is not
the receive fix and may be reverted to the evidence-backed value.

`e4eecb2` separately addresses a real regression: Swift allocated IDs before
unstructured send tasks, which could put a larger ID on the wire first. The
frontend allocates and sends synchronously. Retain the serialized behavior, but
add a deterministic mixed call/subscription test that asserts strictly
increasing wire-send order.

`f8f55f0` strongly fixes the original strict-latest token-starvation mechanism,
but the user again observed lag while 12h was failing. Verify progressive SPS30
frames on a fresh 1h launch, then repeat after the 12h load/recovery. This
distinguishes a scheduler failure from CPU pressure caused by the reconnect/
decode loop. Do not mark the graph symptom resolved on benchmark evidence alone.

`3cd05d5` targets a real formatter hotspot, but its fast parser does not fully
validate hour/minute/second/trailing input and does not apply explicit timezone
offsets. Add equivalence tests for UTC, fractional, offset, and malformed input;
revert or replace the fast path in a new commit if it cannot preserve semantics.

The typed receive policy, production-adapter regression, focused/full suites,
exact live 1h/12h/recovery checks, other-owner health, and pre/post-12h gesture
verification called for by this snapshot are now implemented and passed. See
the authoritative repair status above and the packet's post-transport section.

## 2026-07-18 gesture-render repair update

The SPS30 gesture-end-only redraw regression is repaired. Viewport rendering
now owns one serialized in-flight render and one overwriteable latest pending
request. A completed frame may publish while a newer viewport is pending only
when its data-generation token still matches; data replacement and final
settlement retain strict generation safety. Completion delivery uses the main
run loop's common modes so it remains available during event tracking.

The tracked `Benchmarks/GraphRendering/` release harness records fresh live 1h
and 24h SPS30 sizes, cold/warm production stages, candidate decisions,
min/max-oracle fidelity, and an 8 ms token-storm simulation. In the simulation,
the old strict-latest model publishes zero in-gesture frames; the bounded
scheduler publishes eight, remains at one concurrent render, and settles on the
last token. Fresh live 1h full-resolution rendering measured 3.555 ms median /
5.360 ms p95. A release-app scroll capture recorded 15 distinct SPS30 plot
frames among 20 captures taken before the 1.661-second gesture stream ended.

At the time of this scheduler-only repair, the remaining blocker was the
separate CO2/VOC loading/shared-socket reconnect regression. It is now resolved
by the bounded transport and projection/cache repairs recorded above. The
scheduler repair itself did not change WebSocket ownership, payload limits,
backfill semantics, or the approved future cache/prefetch work.

## Original user-reported regressions (both now repaired and verified)

1. In the running `NativeHAMac`, switch the global graph range to `12h`. The
   `CO2/VOC` history card containing SPS30 entities remains on `Loading history`,
   while the global status alternates between `Live` and `Reconnecting` every
   few seconds.
2. **Scheduler mechanism repaired 2026-07-18; end-to-end check reopened
   2026-07-19:** SPS30 `1h` had progressive live capture, but the user again
   observed lag while 12h failed. Verify it before and after exercising 12h.

The final writer reproduced the first failure in the live app at `1h` after a
prior reconnect: the status was currently `Live`, `CO2/VOC` was still
`Loading history`, and Accessibility exposed the persistent message
`History stream failed: Home Assistant WebSocket disconnected`. Other 1h
graphs were rendered. The running app emitted no useful unified-log entries, so
the underlying URLSession receive error/close code is not yet captured.

## Diagnosis and code anchors

No application fix was made in the final pass: the cause was not sufficiently
proven for a safe last-minute edit.

- Stable identity/range churn is not the leading explanation. Card owner IDs
  are deterministic paths in
  `Sources/NativeHAMac/DashboardViewModel.swift::cleanCards`, and
  `HistoryRequest.key` includes owner path, selected hours, and ordered entity
  IDs. `setGraphHours` invokes `loadHistories`, which cancels obsolete owners
  then starts missing owners. Still verify request counts in the live model.
- The connection cycling is real global transport state, not merely a card
  label: `DashboardViewModel.load` maps
  `HomeAssistantWebSocketConnection.statusUpdates()` directly to
  `Live`/`Reconnecting` around lines 479-497.
- Confirmed transport cause: `URLSessionHomeAssistantWebSocketTransport` creates a
  `URLSessionWebSocketTask` without configuring `maximumMessageSize`
  (`Sources/NativeHACore/HomeAssistantWebSocketTransport.swift`, task factory
  around lines 35-42). A multi-entity, high-cadence SPS30 replay can be a large
  single WebSocket message. A receive failure reaches
  `HomeAssistantWebSocketConnection.runReceiveLoop` (lines 511-524), tears down
  the shared socket in `handleConnectionFailure` (765-804), and schedules the
  reconnect loop (806-844). The exact 12h frame is 4,912,600 bytes / 102,618
  points versus the 1,048,576-byte default; 1h is about 406 KB and succeeds.
- `HAHistoryStreamCoordinator` deliberately uses `resubscribe: false` and
  recreates a fresh owner from connection status
  (`Sources/NativeHACore/HomeAssistantHistoryStream.swift`, `subscribeFresh`
  412-441 and `connectionChanged` 443-470). A disconnect termination itself is
  ignored at 485-493 because connection status owns recovery. Check whether the
  CO2/VOC owner receives a later `.ready`, whether the fresh subscription is
  acknowledged, and whether repeated oversized replay frames kill it again.
- Initial projection converts every compact sample to an ISO string before UI
  publication (`HAHistoryProjection.series`, roughly 244-283). Cold graph
  preparation then walks the full series. This is substantial for high-rate
  history and should not share an uncancellable interaction path.
- The graph gesture scheduler in
  `Sources/NativeHAMac/CardViews.swift::BitmapLineChart` is mostly pre-Module-01
  code. Viewport changes cancel the previous `Task.detached` and start another
  at user-initiated priority (`scheduleRenders` 513-548,
  `scheduleViewportRender` 550-564, `makeRenderTask` 586-635). Cancellation is
  checked only before `GraphBitmapRenderer.render`; the synchronous render and
  preparation path does not cooperatively stop. Rapid gestures can therefore
  leave cancelled CPU work running, and only the final desired token publishes.
  This is a plausible contributor, but the exact live gesture delay still
  needs instrumentation. Do not “fix” it with a sleep or by removing generation
  checks.
- Module 01 changed the render data token to include `contentRevision` and
  added the visual-test `onRenderReady` hook. Those changes make same-shape data
  invalidation correct; no evidence yet shows that either alone causes the
  gesture-end-only redraw.

## Exact stress evidence already gathered

The stress harness/results are temporary diagnostic artifacts, not current
worktree deliverables:

- Harness snapshot: `/tmp/nativeha-module01-sps30-stress`
- Results: `/tmp/nativeha-module01-sps30-stress-results`
- Logs: `/tmp/nativeha-module01-sps30-*.log`

Important protocol distinction: the successful bulk measurements used the
finite command `history/history_during_period`, which returns one `result`
wrapper with `result[entity]`. Production Module 01 currently uses the live
`history/stream` subscription, which sends `event.states` chunks plus optional
chunk times. They are different server paths and completion semantics; bulk
success does not prove a huge live-stream replay will stay healthy.

Measured finite bulk WebSocket results:

- SPS30 PM1.0, 7d: 586,802 samples in 5.677s over
  `history/history_during_period` (28,310,743 JSON bytes). The alternating REST
  run returned the same sample count in 5.207s.
- SPS30 PM2.5, 14d: 1,173,620 samples. Three measured WS runs averaged 10.385s;
  warm mean 10.451s (56,560,910 JSON bytes). The matching REST sample counts
  were equal; warm REST mean 10.605s.

Production live-stream and graph-path observations:

- One SPS30 PM1.0 `history/stream` 12h replay: 41,988 samples, two chunks/two
  publications, exact accumulator match, 1.980s end-to-end, 0.224s standalone
  re-decode, 0.073s cancel, peak process RSS 256,114,688 bytes, and exact zero
  ownership after cancel/disconnect.
- Live 12h graph pipeline for those 41,988 samples: projection 0.231s, cold
  preparation 1.632s, bitmap 0.0065s; ten warm zoom renders max 5.54ms and ten
  warm pan renders max 4.13ms; peak RSS about 115MB. Cold projection/preparation,
  not warm bitmap drawing, dominates.
- Synthetic 100k: projection 0.563s, preparation 3.906s, peak RSS 129MB; warm
  zoom/pan remained about 6ms or less.
- Synthetic 1m: projection 5.690s, preparation 39.578s, peak RSS 419MB.
  Cancellation was requested but the synchronous task still completed, proving
  ignored cooperative cancellation at this scale.
- Real finite PM2.5 14d payload: 1,173,620 decoded samples, 56,560,910 wire JSON
  bytes; decode 4.598s, projection 9.138s, cold preparation 50.033s, bitmap
  0.0093s, warm zoom max 8.60ms, warm pan max 6.44ms, peak RSS 664,092,672
  bytes. It also completed after cancellation was requested.
- The 7d pending live-stream cancellation probe received no chunks within
  20.286s, then cancelled in 0.251s with exact zero final ownership and about
  30MB peak RSS. This shows local cancellation ownership is prompt even while
  the server has not produced the replay; it does not prove server work stops.
- A stress-harness timing-boundary bug was corrected before the JSON numbers
  above were recorded. Use `graph-real-bulk-pm25-14d.json` and the `-rerun.log`
  values, not any earlier informal console timing. The corrected harness times
  decode, projection, preparation, bitmap, zoom, and pan separately.

Future direction: use finite `history/history_during_period` for bounded
historical backfill (preferably on an isolated connection so a large result
cannot disrupt state/live owners), then use `history/stream` only as the live
tail. Merge at an explicit boundary with stable ordering and no deduplication
unless server semantics require it. Add byte/time/memory budgets, progressive
publication/downsampling, cancellation, and generation gates. This is a design
recommendation for the next module/repair, not authorization to silently change
C01 wire semantics without packet/test updates.

## Module 01 and visual verification state

The packet is `complete`. Historical verifier/repair rounds below explain how
the final evidence was reached:
`docs/reference-context/modules/module-01-history-ws-stream.md`.

- The first fresh verifier passed C01-01 through C01-07 and C01-09 but rejected
  the original C01-08 coarse visual oracle.
- The sole writer then replaced it with layout-aware `1h` template matching,
  five separated bottom-axis glyph regions, two consecutive fresh captures,
  and exact erased-range/erased-axis negative regressions.
- The repair produced 15 unique 992x520 PNGs. Focused GUI tests passed 6/6;
  graph tests 8/8 twice (two existing expected Module 09 markers); history
  integration 3/3 twice; full suite 60 tests with one opt-in live skip and zero
  failures in 47.720s. Graph/check-context and resolver were green.
- In-app image previews can visually differ for byte-identical data URLs; the
  packet records raw PNG crop/component proof. A fresh independent completion
  verdict was interrupted by the stress/live regression report. Re-run it only
  after the two GUI regressions are resolved.

## Current worktree scope

Module 01 and Gemini's follow-ups are committed through `3cd05d5`. At the start
of this bounded refresh, the tracked worktree was clean and only the pre-existing
`sample.txt` was untracked. This refresh changes only the Module 01 manifest,
generated graph, evidence packet/index, and this handoff. The hass-frontend
checkout remains read-only.

## Exact next steps and commands

1. Start with the durable state, not a frontend re-audit:

   ```sh
   cd /Users/jin/Documents/Computer/NativeHA
   git status --short --branch
   node tools/reference-context/check-context.mjs \
     docs/reference-context/generated/module-01.dependencies.json
   node tools/reference-context/test-resolver.mjs
   sed -n '1,260p' todo.md
   ```

2. Inspect the current diff and the contract-revision-2 implementation section
   in the packet. Do not redo the frontend audit while graph/checker stay green.
3. Review the recorded fresh independent GUI verdict and current-tree live
   ownership evidence in the packet. Do not repeat the GUI run unless the diff
   contains a functional change after the verifier snapshot; the only later
   source change was a documentation comment in `Models.swift`.
4. Validation is already recorded; rerun only if the orchestrator changes code:

   ```sh
   swift test --filter HomeAssistantWebSocket
   swift test --filter HomeAssistantHistoryStreamTests
   swift test --filter HistoryStreamIntegrationTests
   swift test --filter GraphRenderingTests
   swift test --filter GUIRenderingAndPerformanceTests
   swift test
   swift build --product NativeHAMac
   swift build --product ha-probe
   swift build --product GraphBench
   swift build --product GraphPyramidBench
   swift build --product HistoryStreamBench
   swift test -c release --filter GraphRenderingBenchmarkTests
   git diff --check
   ```

5. Inspect the refreshed graph/checker/resolver output and `git diff --check`,
   commit the intentional Module 01 files without `sample.txt`, and mark Module
   01 complete only if no C01-01-through-C01-09 discrepancy remains.

## Remaining follow-up

- Keep `sample.txt` untouched and perform the intentional Module 01 commit.
- Begin Module 04 research from the reference-context index after the commit.
- Convert temporary stress evidence into a deliberate tracked diagnostic/test
  only if it is maintainable; do not copy the multi-megabyte raw JSON fixtures.
- Decide and document finite backfill/live-tail ownership, payload limits,
  progressive preparation/downsampling, memory budget, and cancellation.
