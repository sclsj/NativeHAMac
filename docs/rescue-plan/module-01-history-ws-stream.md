# Module 01: History API - Switch To WebSocket `history/stream`

Original Claude module: `1. History API: Switch to WebSocket history/stream`.

Priority: critical. Depends on module 02. Coordinate with module 12 because the live dashboard encodes graph windows in Lovelace views/cards, not a global graph-hour control.

## Goal

Replace NativeHA's app-facing history pipeline with Home Assistant's WebSocket `history/stream` semantics so history cards and detail charts receive the same compact, streaming, incremental data model as hass-frontend.

Do not remove the REST history client from command-line tools until those tools are migrated or explicitly retired. The immediate app target is `NativeHAMac`.

## Confirmed Current-Code Findings

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantRESTClient.swift:29` fetches REST `/api/history/period/<start>` with `filter_entity_id`, `minimal_response` set as a nil query value, and `significant_changes_only=0`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:81` defines `HAHistoryPoint` in REST shape: `state`, `attributes`, `last_changed`, `last_updated`, `entity_id`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:466` loads history through `restClient.fetchHistory(...)`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:299` keys card history as `"\(selectedGraphHours):<entities>"`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:754` creates history requests with `selectedGraphHours`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:778` rewrites every cleaned `LovelaceCard.hoursToShow` to `selectedGraphHours` at line `808`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift:235` displays `model.selectedGraphHours` in each history card, not the card's own `hours_to_show`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:650` appends live `state_changed` events into REST history using only non-empty states. That is acceptable for timeline preservation, but it should not be the primary history update path after `history/stream`.
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHACoreTests/HistoryGraphSupportTests.swift:56` already protects the corrected behavior that `unknown` and `unavailable` remain timeline segments with distinct colors.

## Reference Findings

- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:78` defines compact WebSocket `EntityHistoryState` as `{ s, a, lc?, lu }`, with timestamps in Python seconds.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:141` implements `HistoryStream`, which merges stream chunks and trims old states for time-window subscriptions.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:239` exposes `subscribeHistoryStatesTimeWindow(...)`, which sends `type: "history/stream"`, `entity_ids`, recomputed `start_time`, `minimal_response`, `significant_changes_only`, and `no_attributes`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:270` explains why reconnect handling must create a fresh stream and recompute `start_time`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:327` notes that with `minimal_response`, only first/last states usually include attributes, except domains in `DOMAINS_USE_LAST_UPDATED`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:335` processes timeline entities without filtering `unknown` or `unavailable`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts:386` processes line chart entities and uses `last_updated` for `climate`, `humidifier`, and `water_heater`.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts:95` uses per-card `hours_to_show || DEFAULT_HOURS_TO_SHOW`.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts:152` subscribes each history card to the stream window for its configured entity IDs and hours.

## Corrected Semantics

Confirmed issue: NativeHA's history source and cache shape do not match hass-frontend. The app should move to `history/stream`.

Corrected Claude finding: do not drop `unknown`, `unavailable`, or `none` at ingestion. Hass-frontend timelines preserve state transitions. Only line graph preparation should ignore samples that cannot produce numeric chart values.

Hypothesis to verify during implementation: Home Assistant's raw subscription callback may deliver history payload under an `event` envelope, depending on how the Swift client normalizes subscription messages. Module 02 should expose subscription callbacks with the payload already normalized, but module 01 tests should include both raw shapes if the lower layer supports them.

## Target Architecture

Add a WebSocket history API in `NativeHACore`:

- `HACompactHistoryState`: compact stream point with `state`, `attributes`, `lastChangedSeconds?`, `lastUpdatedSeconds`.
- `HAHistoryStreamMessage`: `states: [String: [HACompactHistoryState]]`, optional `startTime`, optional `endTime`.
- `HAHistoryStreamAccumulator`: pure Swift type equivalent to hass-frontend `HistoryStream`.
- `HomeAssistantWebSocketClient.subscribeHistoryStatesTimeWindow(...)`: sends `history/stream` and returns an async unsubscribe handle.
- Adapter functions from compact history to the existing `HAHistorySeries`/`HAHistoryPoint` graph inputs, or a new app-facing `HAHistorySeries` that can represent compact seconds natively.

Use the existing `HAHistorySeries` and `HAHistoryPoint` only if the adapter is clearly centralized. Do not scatter compact-to-REST timestamp conversion through UI code.

Dashboard behavior:

- Each `history-graph` card owns its own history subscription keyed by stable card identity, entity IDs, and the card's `hoursToShow`.
- Detail sheets can subscribe to a separate 24-hour window for the selected entity, or reuse a shared history subscription manager keyed by `(entityID, hours)`.
- `state_changed` subscriptions keep the entity cache fresh. They should not also append duplicate history points for streams that are already subscribed.
- `history/stream` subscriptions should be canceled when their card/view/detail owner disappears or its key changes.

## Implementation Tasks

1. Implement compact history models in `NativeHACore`, probably in `Models.swift` or a new `HistoryModels.swift`.
   - Decode `s` as `state`.
   - Decode `a` as `[String: JSONValue]`, defaulting to `{}` only if the server omits it.
   - Decode `lc` as optional `Double`.
   - Decode `lu` as required `Double`.
   - Preserve seconds precision and fractional seconds if present.

2. Implement `HAHistoryStreamAccumulator`.
   - First non-empty message initializes `combinedHistory`.
   - Empty message means replay is complete, not failure.
   - Merge existing and incoming entity histories.
   - Sort if incoming data is older than the last combined point.
   - For `hoursToShow`, purge old history while preserving the last expired state at the cutoff boundary with `lc` cleared, matching hass-frontend lines `197-223`.

3. Implement attribute policy equivalent to `entityIdHistoryNeedsAttributes`.
   - Needs attributes if the entity is not in current states.
   - Needs attributes for `climate`, `humidifier`, `input_datetime`, `water_heater`, `person`, and `device_tracker`.
   - Otherwise use `no_attributes: true` for lower payload size.
   - Keep current entity attributes available to graph classification and display.

4. Add WebSocket command support after module 02.
   - Send `type: "history/stream"`.
   - Include `entity_ids`, recomputed `start_time`, `minimal_response: true`, `significant_changes_only: true` by default, and calculated `no_attributes`.
   - Return an unsubscribe closure.
   - If reconnect is implemented in module 02, rebuild fresh accumulator state and recompute `start_time` on resubscribe.

5. Replace app-facing REST history loading in `DashboardViewModel`.
   - Remove `loadHistories()` from the normal card path or make it a fallback only.
   - Remove global `selectedGraphHours` from history request construction.
   - `historyKey(for:)` must include card-scoped hours, stable card identity, and ordered entity IDs.
   - `historyEntityIDs(for:)` should use the decoded Lovelace card config after module 04 and should not apply personal hidden-entity filters except through module 03 user preferences.

6. Preserve per-card `hours_to_show`.
   - Stop rewriting `LovelaceCard.hoursToShow` in `cleanCards`.
   - Use `card.hoursToShow ?? 24` for history cards, matching hass-frontend's default.
   - Update the card header display to show the card's actual window.

7. Define transition behavior for active views.
   - After module 12, subscribe only to history cards in the selected view plus any active detail sheet.
   - Before module 12, do not subscribe hidden live views if they are not rendered.

8. Keep REST history safe for tools.
   - Leave `HomeAssistantRESTClient.fetchHistory` available for `GraphBench`, `GraphPyramidBench`, and `HAProbe` until separate plans migrate them.
   - Add tests so REST and WebSocket history shapes are not confused.

## File Ownership And Scope

Likely files to edit in future implementation:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantWebSocketClient.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/HomeAssistantHistoryStream.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- Tests under `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHACoreTests/`

Out of scope:

- Full recorder statistics merge. Hass-frontend fetches statistics for long windows; NativeHA can defer this until history stream parity is stable.
- Broad Lovelace card support beyond current dashboard card types.
- Source-code changes during this documentation task.

## Tests And Verification

Follow the shared harness and reference-approval rules in [`../visual-testing.md`](../visual-testing.md). Likely additions are `Tests/NativeHACoreTests/HomeAssistantHistoryStreamTests.swift`, `Tests/NativeHAMacTests/HistoryStreamIntegrationTests.swift`, and history-stream cases in `Tests/NativeHAMacTests/GUIRenderingAndPerformanceTests.swift`.

### Unit tests

- Decode compact states with `lc` present and absent; decode `a` as an object, missing, and empty; reject or deliberately handle malformed `s`/`lu`; and preserve fractional-second precision.
- Convert compact timestamps to the centralized graph representation consistently. Assert that compact WebSocket fixtures cannot accidentally enter the REST decoder and vice versa.
- Cover accumulator initialization, replay-complete empty messages, multiple entities, duplicate boundaries, out-of-order chunks sorted by `lu`, incremental entities not present in the replay, and deterministic merge ordering.
- Drive trimming with an injected fixed clock. Preserve the last expired state at the cutoff, move its `lu` to the cutoff, clear `lc`, and avoid duplicating an existing cutoff state.
- Preserve `unknown`, `unavailable`, and `none` in timeline input; skip only nonnumeric samples in numeric line preparation without mutating stored history.
- Assert attribute-request policy for present/missing entities and every `NEED_ATTRIBUTE_DOMAINS` domain named above.
- Assert that stable card keys distinguish ordered entity sets and `1`, `3`, and `12` hour cards. Add a semantic contract test against `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts`: each card retains its own `hours_to_show`. The existing narrow `XCTExpectFailure` in `GraphRenderingTests.swift` may remain only until this implementation fixes the gap, then must be removed.

Use small hand-written JSON fixtures for edge cases and generated, fixed-timestamp compact messages for scale. Do not read the live server or a token file.

### Integration tests

Use the Module 02 fake dispatcher/transport, a controllable clock, and a `@MainActor` `DashboardViewModel` fixture:

- Verify the exact `history/stream` subscribe payload, normalized callback shape, matching unsubscribe command, and fresh `start_time` plus fresh accumulator on reconnect.
- Start a history card in its loading state, deliver a finite initial replay, wait with a bounded expectation/poll until the graph render model is ready, then deliver an incremental chunk and assert that the visible model changes.
- Subscribe two cards with overlapping entities. An update for one subscription must not mutate the other card's cache or render model.
- Keep simultaneous `1h`, `3h`, and `12h` cards and assert independent cutoffs, keys, requests, and rendered windows after the same clock advance.
- Cancel on card/view disappearance, profile change, and explicit unsubscribe. A late callback after cancellation must not publish UI state or recreate the card cache.
- Reconnect after replay and verify one fresh subscription, no duplicate samples, and no stale pre-disconnect accumulator merge.

### GUI rendering and visual regression

This module owns a visible integration result even though Module 09 owns graph drawing. Add `@MainActor` offscreen history-card tests using the existing `MacViewPNGRenderer` pattern: `NSHostingView` in a small borderless AppKit window, captured with `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`. Do not use SwiftUI `ImageRenderer`, which is unavailable for macOS 12/Xcode 13.4.1.

- Render a `496 x 260`-point card at display scale `2` for a fixed numeric replay and for a state-timeline replay containing `off`, `on`, `unknown`, and `unavailable`. Use the same size for loading/replay/update comparisons, a fixed UTC source timestamp, and an explicit `Asia/Shanghai` display timezone where the production formatter permits it.
- Capture the initial loading state, the settled replay, and the settled incremental-update state. Use bounded settlement polling for a rendered data region rather than an arbitrary long sleep; assert the replay and update PNGs are distinct.
- Always write inspectable artifacts such as `history-stream-numeric-replay.png`, `history-stream-numeric-update.png`, and `history-stream-timeline-replay.png` to `.build/render-artifacts/`. Check PNG signature, exact pixel dimensions, nonblank content, graph/timeline color families, and that the replay is beyond the loading indicator before any baseline comparison.
- Manually compare those artifacts with the identical entity states/window in `/Users/jin/Documents/HA/hass-frontend`. Only reviewed images may enter `Tests/NativeHAMacTests/ReferenceImages/`, labelled with the baseline macOS version and compared tolerantly. A screenshot does not prove merge ordering, window correctness, cancellation, or duplicate prevention; the semantic tests above do.

### Animation and interaction

Do not add scheduler-driven animation tests to the stream layer. Treat loading, replay-ready, and incremental-ready as explicit deterministic states and render those states directly. If the integration adds a graph data-transition animation, expose its progress and render start/midpoint/end (`0`, `0.5`, `1`), assert distinct intermediate output and that the final frame equals the nonanimated final render, and cover reduced motion if the production API supports it. Trackpad, hover, and pan behavior belongs to Module 09.

### Performance and lifecycle

Add separate XCTest measurements so stream work is not hidden inside bitmap cost:

- In `NativeHACoreTests`, measure cold merge of a generated `20,000`-sample initial replay, warmed incremental processing of `100` successive `200`-sample chunks, adversarial out-of-order chunks, and repeated window trimming. Construct and decode fixture data outside a merge-only measured block when the test is intended to measure merging.
- In `NativeHAMacTests`, separately measure bitmap rendering of the already-merged model. Do not include JSON decoding or accumulator work in the graph-render measurement.
- Measure at least `100` subscribe/unsubscribe cycles with a fake transport, reconnect cycles with fresh accumulators, cancellation, and card/view disappearance. Assert receive/subscription storage returns to its pre-cycle count and use weak references or an equivalent lifecycle probe to show the coordinator/view model is released.
- Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`; warm caches before warm interaction measurements, consume the merged history/render result, and store XCTest baselines rather than requiring aggressive fixed milliseconds. A deliberately loose safety ceiling is acceptable only with its rationale documented.

Xcode 13.4.1 has no `XCTHitchMetric`. True event-to-frame hitch and trackpad tests are deferred to a future XCUITest app target under newer Xcode; they are not a completion gate here.

### Manual QA

- On the live dashboard, compare `Home`, `3h`, and `12h` with hass-frontend and confirm every card uses its configured window; no global hour tab changes all graphs.
- Confirm initial replay becomes visible, incremental states arrive without duplicates, numeric gaps remain gaps rather than zeroes, and timeline `unknown`/`unavailable` spans remain visible.
- Disconnect/reconnect and verify a fresh replay without stale merging. Reopen/close a detail sheet and switch views repeatedly to confirm subscriptions cancel and no post-disappearance updates occur.

## Risks

- A naive adapter may lose attributes needed for climate/person/device_tracker timelines under `minimal_response`.
- Double-appending `state_changed` plus `history/stream` updates will create duplicate or near-duplicate points.
- Keeping `selectedGraphHours` during the transition will hide bugs because all cards appear to use the same request window.
- Reconnect behavior is easy to get subtly wrong: hass-frontend explicitly avoids reusing the old accumulator and stale `start_time`.
- A GUI snapshot can look correct while two card caches alias each other or while duplicate/out-of-order samples exist. Keep stream semantics and view-model isolation assertions separate from visual checks.
- Unbounded settlement sleeps and combined merge-plus-render measurements will make regressions flaky or impossible to attribute; use bounded readiness and separate measurements.

## Acceptance Criteria

- NativeHA app history cards no longer call REST `/api/history/period` during normal dashboard rendering.
- WebSocket `history/stream` supplies initial replay and live updates.
- Each history card respects its own `hours_to_show`, defaulting to 24 when absent.
- `unknown`, `unavailable`, and other non-empty state strings are preserved in timeline data.
- Numeric line graph preparation filters only nonnumeric samples for line rendering.
- All history subscriptions are cancelable and do not leak when views/cards/detail sheets disappear.
- Core decoding/accumulator, fake-stream integration, card-isolation, reconnect, and cancellation tests pass without network access or credentials.
- Numeric and timeline stream fixtures produce valid settled PNG artifacts at the documented size; any enforced reference was manually approved against hass-frontend and uses tolerant comparison.
- Cold replay, incremental/out-of-order merge, trimming, bitmap rendering, and repeated subscription lifecycle measurements have stored XCTest baselines with no unexplained retained memory.
- The per-card-hours conformance expectation is a normal passing assertion; no permanent `XCTExpectFailure` remains for behavior fixed by this module.
