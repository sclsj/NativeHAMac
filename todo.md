# NativeHA Module 01 continuation handoff

Date: 2026-07-17. This is the authoritative next-agent handoff after Module 01
implementation, two visual-settlement repairs, independent verification, live
SPS30 stress work, and a final time-boxed GUI regression diagnosis. Do not mark
Module 01 complete until the two live regressions below are fixed and rechecked.

## Immediate user-reported regressions

1. In the running `NativeHAMac`, switch the global graph range to `12h`. The
   `CO2/VOC` history card containing SPS30 entities remains on `Loading history`,
   while the global status alternates between `Live` and `Reconnecting` every
   few seconds.
2. On an SPS30 graph, including at `1h`, continuous scroll/zoom/pan changes do
   not visibly redraw the graph until the gesture ends. The user identifies
   this as a clear regression.

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
- Likely transport cause: `URLSessionHomeAssistantWebSocketTransport` creates a
  `URLSessionWebSocketTask` without configuring `maximumMessageSize`
  (`Sources/NativeHACore/HomeAssistantWebSocketTransport.swift`, task factory
  around lines 35-42). A multi-entity, high-cadence SPS30 replay can be a large
  single WebSocket message. A receive failure reaches
  `HomeAssistantWebSocketConnection.runReceiveLoop` (lines 511-524), tears down
  the shared socket in `handleConnectionFailure` (765-804), and schedules the
  reconnect loop (806-844). This matches the symptom but remains **likely, not
  confirmed**, until the concrete URLSession error/close code and frame size
  are recorded.
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

The packet remains `verification-ready`, not complete:
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

No source/test fix was made during this final regression pass. `todo.md` and a
short packet hold note are the only intended additions from it. The broader
uncommitted Module 01 implementation already contains:

- Modified: `Package.swift`, seven Module 01 core/macOS source files,
  `Tests/NativeHAMacTests/GUIRenderingAndPerformanceTests.swift`,
  `Tests/NativeHAMacTests/GraphRenderingTests.swift`, configurability/reference
  docs, Module 01 manifest/generated graph/packet/index.
- Untracked intended deliverables: three `Benchmarks/history-stream` files,
  `Sources/NativeHACore/HomeAssistantHistoryStream.swift`, three core history
  test files, and `Tests/NativeHAMacTests/HistoryStreamIntegrationTests.swift`.
- Do not stage/commit until the orchestrator/user requests it. Preserve all
  current changes. The hass-frontend checkout was read-only and clean.

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

2. Reproduce on the current configured server with one diagnostic run. Record
   timestamped connection state, concrete URLSession receive error/domain/code,
   WebSocket close code/reason if available, active history owner key/entity
   count/range, incoming frame byte count, and connection debug snapshot. Never
   log the token or full payload. Check `URLSessionWebSocketTask.maximumMessageSize`
   before `resume`; test a safely bounded increase with a fake-adapter regression
   before any live trial.
3. Determine the exact CO2/VOC entity list and measure its 1h/12h result bytes.
   Compare a single entity with the whole card and confirm whether failure is a
   size limit, server/proxy close, decode failure, timeout, overflow, or owner
   restart loop. Do not infer from global `disconnected` alone.
4. Instrument the live gesture path with counts/timestamps for scroll callbacks,
   state/token changes, render task starts/cancellations/completions, cache hit,
   preparation duration, and publication. Establish whether SwiftUI defers the
   viewport state during event tracking or uncancellable renders pile up.
5. Implement the smallest evidence-backed repair with deterministic tests.
   Candidate architecture is isolated finite backfill + live tail and a
   cancellable/coalesced prepared rendering pipeline, but neither is a trivial
   one-line change. Preserve latest-generation publication semantics.
6. Minimum validation after a repair:

   ```sh
   swift test --filter HomeAssistantWebSocket
   swift test --filter HomeAssistantHistoryStreamTests
   swift test --filter HistoryStreamIntegrationTests
   swift test --filter GraphRenderingTests
   swift test --filter GUIRenderingAndPerformanceTests
   swift test
   git diff --check
   ```

   Then manually confirm 1h and 12h CO2/VOC settle without global reconnect,
   continuous zoom/pan visibly redraws during the gesture, other history owners
   remain live, and final ownership is zero after teardown. Update the Module 01
   packet/graph and dispatch a fresh independent verifier.

## Unfinished work

- Confirm/fix the 12h CO2/VOC shared-socket reconnect/loading regression.
- Confirm/fix continuous SPS30 gesture redraw without weakening cancellation or
  visual correctness.
- Convert temporary stress evidence into a deliberate tracked diagnostic/test
  only if it is maintainable; do not copy the multi-megabyte raw JSON fixtures.
- Decide and document finite backfill/live-tail ownership, payload limits,
  progressive preparation/downsampling, memory budget, and cancellation.
- Re-run the fresh independent Module 01 verifier and only then decide whether
  status may become `complete`.
