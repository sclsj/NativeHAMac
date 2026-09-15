# NativeHA readiness and instruction audit — 2026-09-11

Audited NativeHA `adc2c036156b705b3fc778be43bb4404b231e978` on a clean `main`, against local hass-frontend `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. Environment: macOS 12.6.7, Apple Swift 5.6.1 / Xcode 13.4.1, arm64.

## Current disposition — user follow-up, 2026-09-11

The user deferred A1 and A2: both are confirmed synthetic-input failures, but reachability from this HA deployment has not been established. They remain open; this is neither a claim that HA can produce these inputs nor that it cannot. A3 is deferred to the dedicated graphing module, whose broader product scope will be specified later. No climate or graph implementation changes are part of this follow-up.

A4 is addressed by consolidating the injected-client test entry point onto the same weak-owner bootstrap runner used by production startup, removing the unused load path and duplicate installation/failure helpers. The shared path awaits retired status ownership, cancels an uninstalled Lovelace subscription if the final entity-generation proof fails, and ignores errors from superseded bootstrap candidates. Production lifetime ownership remains weak.

The original findings and validation below describe the audited revision. Their “repair next” recommendations are superseded by this disposition. Module 08 research may proceed; deferred A1–A3 are no longer a prerequisite stabilization gate. Preserve verified ownership contracts in subsequent work.

### Follow-up validation and plan corrections

On base `9291da336d2f068c39c4924fed3add4c52c27f85` with this follow-up diff:

| Check | Result |
|---|---|
| `swift test --filter DashboardBootstrapLifecycleTests` | 26 tests, 0 failures; 6.6 seconds, including 100 full reconnect/retry/stop cycles and actual production-bootstrap weak-release coverage |
| `swift test` | 320 executed, 5 opt-in skips, 0 unexpected failures; existing expected hover failure retained; 89.5 seconds |
| `swift build -c release --product NativeHAMac` | Pass; 22.5 seconds on macOS 12 / Swift 5.6.1 |
| Refreshed graphs and strict context checks for 01, 02, 04, 05, 06, 07, 09, 12 | All green; TypeScript nodes/edges unchanged, NativeHA anchors refreshed |
| `node tools/reference-context/test-resolver.mjs` | Pass; 31 nodes / 61 edges |
| Independent Swift/test diff review | No medium-or-higher finding; reviewer inspected source and consumed the focused test result, without separately rerunning tests |

The new required-response fixture holds an old Lovelace request, installs a new dashboard, then rejects the old request. It asserts old socket cleanup, continued readiness and entity delivery from the winning client, and final stop cleanup. Existing dead-candidate and deinitialization tests now protect the same runner as production. No live HA, matched-reference visual, or manual interaction checks were performed for this ownership-only source change.

The rescue index and all twelve module plans now distinguish historical proposals from current scoped evidence. Targeted corrections cover completed transport/entity/identity work, skipped profile prerequisites, exact weather flag/action and entity-row contracts, Markdown's already-preserved options, source-content validation versus rendered-empty behavior, `entity_id` array handling, graph test status, and the unapproved fan-control threshold proposal. The Module 05 packet also corrects its address-fallback overstatement: fallback covers REST config discovery, not required WebSocket bootstrap failure. Further Module 08 implementation still requires complete researched evidence and independent research review.

## Original audit verdict

The rescue is making substantial progress. Keep the native architecture and the repaired transport, history, identity, navigation, entity, and weather contracts. The project does not need another rewrite. However, insert a bounded stabilization gate before the next feature implementation: two reproduced high-impact safety failures, graph correctness/test gaps, and a duplicated bootstrap path deserve attention now.

“Module complete” means its scoped contracts passed the recorded verification; it does not mean the whole app or original module plan is complete. Module 03 is intentionally skipped. Weather-card forecast and broad graph/climate/fan parity remain explicit deferrals. Those are not new regressions.

## Original findings and recommendations

### A1 — High: missing climate temperatures crash detail rendering

Source: `Sources/NativeHAMac/CardViews.swift`, `EntityDetailSheet.detailContent` (line 1570), `ClimateDetailContent.body` (line 1641), and the temperature getters (lines 1739–1745).

`currentTemperature` falls back to `targetTemperature`, which falls back to `currentTemperature`. With both attributes absent, null, or unparseable, neither getter terminates. Any existing climate state reaches the specialized detail view, including a sparse `unavailable` state. Disabling its controls does not prevent SwiftUI from evaluating the body.

The isolated probe evaluates the actual compiled `ClimateDetailContent.body` with an unavailable climate state and empty attributes: **SIGSEGV, exit -11**. No server mutation or live device failure was needed. This is a reproducible failure condition, not a claim that the user's current climate entity is currently missing these attributes.

Reference: `src/dialogs/more-info/controls/more-info-climate.ts::render` treats missing current temperature as absent display content. Its current-temperature row is guarded by `currentTemperature != null`.

Repair next: resolve optional current/target values without recursion, provide a noninteractive missing-data state where necessary, and add sparse/null/ unavailable detail-render tests. Keep full climate capability work in Module 10; this crash does not need that entire module.

### A2 — High impact, input-dependent: numeric-axis generation can run forever

Source: `Sources/NativeHAMac/GraphRendering.swift::numericValue` (line 831), `GraphPreparedSeriesCache.prepareFull` (line 1061), and `niceAxis` (line 1537).

Numeric conversion accepts `Double("inf")`. For values `[1, +infinity]`, axis padding produces infinite endpoints. `niceNumber` returns 1 for the nonfinite step, then the tick loop repeatedly adds 1 to negative infinity, which never advances. The array grows without a termination or cancellation check.

A finite case fails too: `[1e20, 1e20]`. At that magnitude, the small padding and increment round away, so the tick value never changes. Checking input finiteness alone is therefore insufficient.

Both fixtures were passed through the **production GraphBitmapRenderer**, not just a copy of the axis formula. Both exceeded the isolated 0.3-second deadline and were killed. The loop analysis establishes why they cannot terminate; the timeout alone is not the proof. Running off-main prevents an immediate main-thread block but does not bound CPU/memory or let this loop observe cancellation. These values were synthetic; their frequency in live history was not measured.

Reference: `src/components/chart/state-history-chart-line-data.ts` uses `safeParseFloat` to reject nonfinite values and `trackY` checks finiteness.

Repair next: reject nonfinite numeric samples while preserving appropriate gap semantics, calculate representable finite axis bounds/steps, and bound tick generation with an explicit progress invariant. Add finite-extreme, overflow, NaN/infinity, and ordinary-range tests. No renderer rewrite is required.

### A3 — Medium: graph semantics are wrong and a conformance test falsely passes

Sources: `GraphRendering.swift::GraphRenderResult.sample` (line 173), `GraphBitmapRenderer.drawBitmap` (line 588), `visibleRange` (line 1415), and `Tests/NativeHAMacTests/GraphRenderingTests.swift` (lines 214–275).

Three production-object observations use the same two points, 10 at time 0 and 20 at time 100:

- Hover at time 60 returns **20 at time 100**, a future value. The existing expected-failure test reproduces this and does not fail the suite.
- Numeric drawing connects samples directly with `addLine`; it does not construct horizontal-then-vertical step-end geometry. The existing test's 100-second transition occupies only about 5.6 logical pixels inside a 3,600-second viewport. Its radius-2, either-orientation blue-pixel check passes against that diagonal line. Keeping the renderer, values, image dimensions, and pixel oracle unchanged but using a 100-second viewport makes the assertion **false**. This is a demonstrated test false positive.
- Zooming to `[25,75]` returns **nil render**, because `visibleRange` retains only points whose timestamps lie inside the viewport. The state active in that interval exists in the loaded data, but neither raw sample lies inside the viewport, so the graph disappears.

Reference: `state-history-chart-line-data.ts::generateStateHistoryChartLineData` sets `step: "end"`, handles null gaps, and extends final values to the requested end. `state-history-chart-line.ts::_renderTooltip` uses the last datapoint before the axis time when resolving a missing dataset point. These contracts are also recorded in the existing Module 09 plan.

Repair before further feature work: establish a strong geometry oracle, fix step-end/viewport-boundary/gap behavior and previous-sample hover together, and test hover against unsampled source data so min/max reduction does not become the tooltip's authority. Preserve the verified off-main coordinator and spike-retaining sampling. Remove the hover expected failure only after its contract passes. Keep broader axis polish, range expansion, prefetch, and cache redesign in their later stages.

### A4 — Medium technical debt: tests and startup have separate bootstrap implementations

Source: `Sources/NativeHAMac/DashboardViewModel.swift`: production entry at `startImmediatelyIfCurrent` (line 471), `runOwnedBootstrap` (1242), unused private `load` (1545), `bootstrapDashboard` (1571), and `installBootstrapOwnership` (1788). See direct `bootstrapDashboard` calls throughout `DashboardBootstrapLifecycleTests.swift`, including line 20.

Production startup uses the weak-owner static bootstrap. Many bootstrap fixtures call a separate instance implementation with its own metadata fetch, candidate installation, retirement, and failure logic. There are also tests using `lifecycleBootstrapClientOverride` and the real `start()` route, so this is not a claim that production startup has no coverage. The problem is that fixing/testing one implementation does not necessarily fix/test the other.

The split already differs: production retirement awaits the old status task; the instance installation path cancels it without awaiting it at that point. That difference is evidence of duplication drift, not a separately established user-visible bug. The view model remains 3,942 lines; the history collaborator is mainly a 40-line state container, so broad decomposition is still partial. File length alone is not the defect.

Before adding Markdown subscription ownership, consolidate bootstrap onto one execution path while keeping weak lifetime ownership and injectable transports. Route existing adversarial tests through that path and remove the unused load implementation. Preserve app-generation and single-owner-tail contracts; do not use this finding as justification for a wholesale view-model rewrite.

## What can remain staged

- Preserve Modules 02/01/04/12/05/06/07's verified scoped behavior. Fresh source checks and the full suite support continuing from this foundation.
- Keep Module 03 skipped under the fixed-deployment decision; do not add profiles, authentication migration, or a settings UI as cleanup.
- Broader Module 09 smooth-axis work, history expansion, byte-budgeted cache, and idle prefetch remain planned. The previously documented stale-viewport fallback is safe but potentially wasteful; no new live measurement here establishes a need to prioritize that optimization ahead of A1–A4.
- Full climate/fan capabilities remain Modules 10/11 after the safety patch.
- Module 08 can be researched independently. Its plan previously instructed static content never to subscribe, contradicting `hui-markdown-card.ts::_tryConnect`, which does not inspect template markers. That stale instruction and its test/acceptance copies are corrected in this commit. Full renderer/template lifecycle research is still required.

## Instruction cleanup

Consolidated the root, four routes, and module workflow from **372 to 229 lines**. Product intent and configuration surfaces are unchanged.

- Shared worktree, documentation-maintenance, source-reading, and commit rules live at the root instead of being repeated in every route.
- Ordinary task routing stays narrow; an instruction-review request explicitly allows reading the instruction files. A request to fix a bug no longer needs magic route words to authorize the requested repair.
- Fresh packets narrow reference research, while the relevant code still gets read. Removed the contradiction between always rereading old plans and using the fresh packet as the implementation scope.
- Packet updates depend on changed evidence/status, not every turn ending. Removed obsolete Module 02 copy-paste instructions and app-specific context management commands from the generic module workflow.
- Delegation is bounded and useful rather than a requirement to keep the main agent permanently dispatch-only. Algorithm comparisons focus on plausible candidates when measurements can change the implementation decision.
- Marked legacy instruction proposals/scaffold research as historical and corrected the visual-testing guide's obsolete three-expected-failures claim.

## Original audit validation and limits

Fresh checks on the audited source:

| Check | Result |
|---|---|
| `swift test` | 319 executed, 5 opt-in skips, 0 unexpected failures; 1 expected hover failure; 88.5 seconds |
| `swift build -c release --product NativeHAMac` | Pass; 20.1 seconds |
| `node tools/reference-context/test-resolver.mjs` | Pass; 31 nodes / 61 edges |
| `check-context.mjs` for 01, 02, 04, 05, 06, 07, 09, 12 | All green; anchored files match |
| Isolated production-object audit probe | Climate SIGSEGV; both axis fixtures timed out; step-test false positive and empty viewport reproduced |

The five opt-in skips cover live/benchmark checks, not failed offline tests. The current test run generated offscreen GUI artifacts, but this audit did not perform a fresh matched-reference visual review, physical trackpad session, live service calls, or live server smoke. No approved PNG baselines are checked into `Tests/NativeHAMacTests/ReferenceImages`; existing module visual reviews remain historical evidence, not automatic pixel-regression enforcement.

This was a broad readiness assessment with deep checks of the graph, detail, bootstrap, and instruction paths, not a new line-by-line verification of every transport/weather contract. Interrupted parallel audits did not establish a fresh exhaustive transport verdict. Source hashes show freshness, not correctness. No application source or existing tests were edited.

## Reproduction and handoff

From the repository root, after `swift test`:

```sh
python3 docs/audits/2026-09-11-readiness-probe.py
```

The adjacent Swift probe links existing debug production objects, excludes the app entrypoint, disables selected diagnostic logging, and contacts no server. The Python runner isolates each failure in a subprocess, disables core dumps, kills timed-out children, and saves logs in a new temporary directory. This is an audit reproducer with known failures, not a green regression suite or a portable performance benchmark.

Original next step: research Module 08 and independently review its evidence before implementation. Revisit A1/A2 when live reachability evidence or the relevant module scope warrants it; carry A3 and its weak oracle into the later dedicated graphing module. Keep the existing cancellation, identity, and history-lineage guarantees.

## 2026-09-14 Module 10 follow-up

Module 08 has since completed. [Module 10](../reference-context/modules/module-10-climate-detail.md) removes the recursive climate temperature fallback and independently verifies missing, malformed and zero-valued readings through production parsing/rendering regressions, closing A1. Final independent debug validation passed 376 tests with five expected opt-in skips and zero unexpected failures; the release climate suite passed 21 tests. Native/reference control-state visual review passed within its documented scope. Module 10 remains verification-ready pending authorized live actuation acceptance; that gate is separate from the repaired synthetic crash. A2/A3 and broader graph changes remain deferred. The original audit findings and reproduction results above remain historical evidence, not a current implementation verdict.

Subsequent authorized acceptance at 2026-09-15T00:45Z (September 14 local time) passed seven live climate temperature/preset/HVAC calls through production Swift controllers, with authoritative subscription and REST confirmations. Original Off/22.8°C/None settings were restored and independently rechecked. Module 10 is now complete within its documented scope; physical compressor and trackpad/hitch verification are not claimed. The opt-in live harness and raw evidence are linked from its packet.
