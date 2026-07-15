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

Unit tests:

- Decode compact states with `lc` present and absent.
- Decode `a` as object, missing, and empty object.
- Convert compact timestamps to `HAHistoryPoint` ISO strings or native timestamps consistently.
- Accumulator initializes from first stream message.
- Empty stream message keeps current combined history.
- Out-of-order incoming chunks are sorted by `lu`.
- Purging a time window keeps the last expired state at the cutoff with `lc` removed.
- Timeline history preserves `unknown`, `unavailable`, and `none`.
- Numeric graph prep skips nonnumeric points only in the numeric line path.
- `historyKey` differentiates the same entity set with `1`, `3`, and `12` hour cards.

Integration-style tests with a fake WebSocket dispatcher:

- Subscribe sends the expected `history/stream` payload.
- Unsubscribe sends the matching unsubscribe command through module 02.
- A subscription callback updates the right card key without affecting other history cards.

Manual QA on the live dashboard:

- `Home`, `3h`, and `12h` views show history windows matching their Lovelace card config.
- No global hour tab changes every graph at once.
- State timelines show `unknown`/`unavailable` spans if such states occur.
- Numeric sensor graphs still omit nonnumeric gaps instead of drawing bogus zeroes.
- Reopening a detail sheet does not duplicate history points.
- Disconnect/reconnect does not merge stale pre-disconnect history into a fresh replay.

## Risks

- A naive adapter may lose attributes needed for climate/person/device_tracker timelines under `minimal_response`.
- Double-appending `state_changed` plus `history/stream` updates will create duplicate or near-duplicate points.
- Keeping `selectedGraphHours` during the transition will hide bugs because all cards appear to use the same request window.
- Reconnect behavior is easy to get subtly wrong: hass-frontend explicitly avoids reusing the old accumulator and stale `start_time`.

## Acceptance Criteria

- NativeHA app history cards no longer call REST `/api/history/period` during normal dashboard rendering.
- WebSocket `history/stream` supplies initial replay and live updates.
- Each history card respects its own `hours_to_show`, defaulting to 24 when absent.
- `unknown`, `unavailable`, and other non-empty state strings are preserved in timeline data.
- Numeric line graph preparation filters only nonnumeric samples for line rendering.
- All history subscriptions are cancelable and do not leak when views/cards/detail sheets disappear.

