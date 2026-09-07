---
schema: nativeha-evidence/v1
module: "07"
title: Weather card current conditions and forecast ownership
plan: ../../rescue-plan/module-07-weather-card.md
status: research-ready
contract_revision: 1
depends_on: ["02", "04", "05", "06", "12"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 2e9888267d06a92c1a832f6fdabc666fb5d0235f
graph_file: ../generated/module-07.dependencies.json
graph_fingerprint: 329380ee9ac2439d2d70e9396be9d996ab3f4863030ed799edadb5b57deb0774
last_researched: 2026-09-07
last_validated: 2026-09-07
---

# Module 07 evidence packet

## Gate and bounded scope

This packet authorizes one implementation milestone: correct the existing `weather-forecast` card's **current conditions**. Forecast subscription and forecast rows are deliberately deferred because all three live cards specify `show_forecast: false`. The deferred design is pinned below so later work uses the verified Module 02 connection and the Module 05/12 owner seam rather than inventing a card-local lifecycle.

The milestone includes config/name projection, condition labels and icons, temperature/unit/secondary display, show-flag fallback, missing and sentinel states, details action, accessibility, responsive rendering, and tests. It adds no fetch, subscription, persistence key, cache, settings UI, profile behavior, or typed `AppConfig` surface. It preserves Core Graphics and every approved graph-range, WebSocket, history, graph-feed, render-coordinator, tooltip, logging, and Module 04/12 identity policy.

Out of scope: forecast UI and ownership implementation, full weather more-info, radar/maps, animation, MDI assets, arbitrary Lovelace actions, service calls, Modules 08-11, and the separate Module 09 stale-viewport fallback.

## Observable behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Required evidence |
|---|---|---|---|---|
| C07-01 | A resolved `weather-forecast` card is projected | Preserve and expose exact raw `entity`, `name`, `show_current`, `show_forecast`, `forecast_type`, `forecast_slots`, `secondary_info_attribute`, `round_temperature`, and three action fields. String `name`, including `""`, wins; absent name uses the existing entity display name. Structured entity-name config remains raw, uses the same existing display-name fallback, and emits one scoped `unsupported structured weather name` diagnostic; it never invalidates the card. Full structured-name metadata resolution is deferred. | Module 04 path-plus-canonical identity remains the card/SwiftUI identity. Unknown keys and invalid siblings remain raw. No hash, revision, or timestamp implies ancestry/freshness. | Decode/projection tables for absent, false, zero, empty string, structured, invalid, and unknown values. |
| C07-02 | Entity is present and not `unknown`/`unavailable` | Render the bounded weather-specialized condition label, resolved name, condition-specific icon, temperature when numeric, unit, and at most one secondary value. Numeric JSON integer/double and accepted numeric-string forms are handled without traps; malformed attributes are recoverable rather than fabricated. | Presentation is pure over accepted `HAState`, config, server units, locale preferences, and already-fetched metadata. One entity update cannot mutate another card. Event order is irrelevant to current-state display. | Table-driven presenter and integration tests. |
| C07-03 | Condition is one of HA's standard weather states | Map `clear-night`, `cloudy`, `fog`, `hail`, `lightning`, `lightning-rainy`, `partlycloudy`, `pouring`, `rainy`, `snowy`, `snowy-rainy`, `sunny`, `windy`, `windy-variant`, and `exceptional` to isolated SF Symbol presentations and semantic labels. Unknown conditions use one non-sunny fallback icon and a cleaned raw label. | A finite weather-only English label table is permitted only for the fixed live `en` deployment; it does not expand Module 06 generic localization. Preserve raw fallback. A deployment-language change is a stop rule. | Exhaustive icon/label table and unknown fallback tests. |
| C07-04 | Temperature or secondary attribute is rendered | Temperature unit resolution is entity `temperature_unit`, then decoded server `unit_system.temperature`; do not add an `AppConfig` unit preference. The card calls locale-aware `formatNumber` directly: the default is at most two fraction digits and `round_temperature: true` sets at most zero fraction digits. Entity-registry display precision is not consulted. Explicit `secondary_info_attribute` wins and uses its weather unit/format; explicit missing or null secondary data displays `Unknown`, while missing `wind_speed` displays `-`. Absent explicit config follows frontend current-card fallback: forecast extrema when available, then first-forecast precipitation, otherwise current humidity. In this milestone forecast is unavailable, so implicit fallback is humidity. | Server `unit_system` is bootstrap data, not product configuration. Preserve locale-sensitive unit separation through `blankBeforeUnit`; do not replace it with an unconditional space. Unsupported/malformed explicit attributes produce no made-up value. | Unit precedence, default maximum-two-digits, round-to-maximum-zero, no-registry-precision, locale spacing, humidity, wind, pressure, visibility, precipitation, explicit missing/null, and malformed tests. |
| C07-05 | `show_current`/`show_forecast` combinations are evaluated without forecast data | Frontend runtime defaults both flags to visible. Because this milestone has no usable forecast, the current block renders for all flag combinations, including both false, matching `weather = !forecast || show_current !== false`. No misleading forecast placeholder appears. | `forecast_slots` and `forecast_type` remain preserved but inert. The implementation must not subscribe merely because `show_forecast` defaults true. | Four flag combinations, absent flags, slots zero/negative preservation, and no-owner assertions. |
| C07-06 | Entity is missing, `unknown`, or `unavailable` | Missing entity shows an explicit entity-specific missing state and is not actionable. `unknown` and `unavailable` show intentional sentinel content, never appear sunny, and retain the same action affordance as a normal present entity. | Reference parity is authoritative: do not suppress action or focus solely because the accepted state is `unknown` or `unavailable`. Malformed attributes remain recoverable. | Semantic/action/accessibility tests proving missing is disabled and both sentinels use the existing action matrix. |
| C07-07 | Card action or keyboard focus occurs | Absent tap action opens existing details for the configured weather entity. Explicit `more-info` targets `tap_action.entity` when present, otherwise the card entity. Explicit `none` disables it. Malformed or unsupported explicit actions do not fall through to default details. Only already-supported details routing is implemented; hold, double-tap, navigation, URL, service, and other action kinds remain preserved and visibly unsupported without side effects. | Missing cards are not focusable as actionable controls. `unknown` and `unavailable` use this same action matrix and may open details; neither sentinel disables an otherwise enabled action. Space/Return invokes one exact details target when enabled. No service call is made. | Action matrix including explicit target override, malformed/unsupported no-fallthrough, both actionable sentinels, target isolation, keyboard, and accessibility tests. |
| C07-08 | Card renders at normal/narrow widths or state changes | Use a bounded native layout with readable name/condition/temperature/secondary content, stable card identity, no clipping at specified sizes, and no weather animation. State change replaces presentation without owner churn. | No timer/task/subscription is introduced. SF Symbols are an isolated approximation so an icon backend can change later. | 496x150 and 320x190 dark-Aqua captures plus semantic region and transition tests. |
| C07-09 | Future forecast support is enabled in a later gate | Select legacy forecast from state attributes when config type is absent/`legacy`; infer hourly for gaps under 8h, twice-daily under 24h, otherwise daily, only with more than two entries. Modern `hourly`/`daily`/`twice_daily` uses `weather/subscribe_forecast` with exact `entity_id` and `forecast_type`; accept only matching event type with more than two entries. Preserve payload order and slice to `forecast_slots ?? 5`; datetime labels never establish freshness. | This contract is designed but **not permitted in the current implementation**. A later packet revision must activate it and add payload, layout, and visual contracts. | Later fixed legacy/modern payload tests; current milestone asserts zero forecast commands. |
| C07-10 | Future active view/config/reconnect changes forecast demand | Future request identity is exact Module 04 `card.nativeID` + entity ID + modern forecast type. Derive desired requests recursively from the final Module 12 active view. Retain exact intersection; cancel removed/hidden/retyped cards. Use Module 02 `subscribeMessage` resubscribe ownership—never a second receive loop or manual duplicate reconnect. | Integrate with the one existing `dashboardOwnerOperationTail`: synchronously invalidate/detach old startup, acknowledgement, delivery, and subscription authority; await captured cancellation; recheck generation; install only the final request. Callback validates lifetime, exact key, owner generation, and desired membership. Old ack/event/status/completion cannot publish. Stop/deinit/emergency mirrors cancel handles/tasks before WebSocket disconnect. No hashes, `contentRevision`, or endpoint timestamps imply freshness. | Later held-start/cancel/reconnect/A-B-C/A-B-A tests, exact owner counts, late-result rejection, weak-release tests. |
| C07-11 | Candidate reaches release/verification | Focused/full/release, GUI/manual, performance, migration, context/resolver, and authorized read-only live gates pass with no regression to Modules 02/01/04/12/05/06. | No state-changing HA call. Fixed-server bootstrap/token stays unchanged. No new persistence means migration evidence is an explicit no-op. Any new config/product decision, language change, action expansion, owner outside the one tail, identity alias, or regression is NO-GO. | Validation matrix below and independent verifier verdict. |

## Reference decisions and corrections

- Runtime `show_current` and `show_forecast` both default true. The editor's normalization is not runtime authority. Without forecast data, current conditions render even when `show_current: false`.
- The current card renders one configured/fallback secondary attribute. The pressure/wind/visibility/attribution list in `more-info-weather.ts` belongs to the detail dialog and is not card scope.
- A modern `forecast_type` causes hass-frontend to subscribe even if forecast is hidden. NativeHA defers all forecast ownership in this milestone, so it issues zero forecast commands; this has no observable effect on the three live forecast-off cards and avoids speculative hidden work.
- hass-frontend leaves both `unknown` and `unavailable` weather cards actionable. NativeHA follows that reference behavior: missing entities remain non-actionable, while neither sentinel suppresses an otherwise enabled action.

## State machines

### Current milestone

`resolved card -> pure config adapter -> entity lookup -> missing/sentinel or current presenter -> SwiftUI render`. Accepted global entity state continues to come from Module 05. There is no new async state, owner, startup, cancellation, cache, persistence, or generation.

### Deferred forecast lifecycle

`inactive -> desired -> starting -> subscribed -> reconnecting/cancelling -> inactive`. The only authority is an opaque owner generation plus exact request membership on the existing owner tail. Module 02 owns physical-generation resubscription and fresh wire IDs. Cancellation is idempotent and settles before replacement. Event datetimes label forecast items only.

## Source anchors

Reference checkout is clean at `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`. Content hashes are SHA-256; line numbers are navigation hints only.

| Path / symbol | Hash | Behavior pinned |
|---|---|---|
| `src/data/weather.ts`: feature/type models, `getWeatherUnit`, `getSecondaryWeatherAttribute`, `getForecast`, `subscribeForecast` | `386d4da61b41951bf15098c5b1d0ba8b301da27b7ed6602b96d4143bed1f514b` | Units, secondary selection, legacy inference, exact modern command and types. |
| `src/panels/lovelace/cards/hui-weather-forecast-card.ts`: `HuiWeatherForecastCard` | `a176b5201ef2503e7d059df7b12b6d3fd8e16510966aff2eccb1abc34ed58c05` | Runtime defaults/fallback, card layout, slots, action and lifecycle. |
| `src/panels/lovelace/editor/config-elements/hui-weather-forecast-card-editor.ts` | `ab54e6b1a70d34cf35e0f9d1381bea75f5ad6d6373fb2c7b824f231ac8a7bdc2` | Editor validation/defaulting, not runtime semantics. |
| `src/panels/lovelace/cards/types.ts`: `WeatherForecastCardConfig` | `673793f38105ef930569f51465df6b9ff051ac1452a67fa5519507b827c6fe90` | Name/config/action shapes. |
| `src/common/entity/compute_state_display.ts` | `6ae38ab3fbf1f09f3461dbcc9746d8525e9339e268ec6d22850d778f17f89537` | State display boundary. |
| `src/common/entity/compute_attribute_display.ts` | `d407849c07698b512222dce4249c0fdfc86417b9ca9f519fbf402a473fbd03b1` | Explicit attribute formatting. |
| `src/common/entity/compute_entity_name_display.ts` | `289301f8a2dc1184ebfaa637e66cf00d099036533ebefbac39991a1f1397144e` | String/structured/fallback name precedence. |
| `src/common/number/format_number.ts`: `formatNumber`, `getDefaultFormatOptions` | `52dfeb9bd192f3cbc84466548727d98dbfcba32dcbd4ed469ef51bc6d00dee88` | Card-direct locale formatting defaults to at most two fraction digits; the explicit weather option can lower the maximum to zero without entity-registry precision. |
| `src/common/translations/blank_before_unit.ts`: `blankBeforeUnit` | `1e9cea22b62875f83cd64d497e89aba6409562267552a1636a064736ac206351` | Locale- and unit-sensitive separator before weather units. |
| `src/panels/lovelace/common/handle-action.ts` | `f0276cbaa278333684e31cfb56a27b37fe578ace18bebf576d7cab938c82fdfc` | Default more-info and configured action boundary. |
| `src/panels/lovelace/common/has-action.ts`: `hasAction` | `fdae56ecfe56a485528bbc75882f002b4afe3a455bb13eeef19423f9bc211466` | An explicit action other than `none`, including malformed/unsupported action kinds, remains an action and therefore does not become default more-info. |
| npm `home-assistant-js-websocket@9.6.0`, `dist/connection.js`: `Connection.subscribeMessage` | `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8` | Generic reconnect/resubscribe and unsubscribe ownership behind the imported interface. |

The complete reviewed dependency graph is [`module-07.dependencies.json`](../generated/module-07.dependencies.json): 127 nodes, 814 edges, five recorded cycles, zero unresolved entries, zero missing symbols, no truncation, fingerprint `329380ee9ac2439d2d70e9396be9d996ab3f4863030ed799edadb5b57deb0774`. The explicit npm runtime seed is required because `weather.ts` calls through an imported `Connection` interface; a static source-only trace would not prove the resubscription behavior. Traversal stops after the weather card's direct render/format/action dependencies and the connection runtime; editor form internals in recorded cycles do not decide runtime card behavior.

## Native mapping and implementation order

| Order | Contracts | Permitted path | Required change |
|---:|---|---|---|
| 1 | C07-01, C07-04 | `Sources/NativeHACore/LovelaceModels.swift`, `Sources/NativeHAMac/LovelacePresentation.swift` | Project all already-preserved weather fields without changing resolved identity; repair weather name handling without invalidating raw config. |
| 2 | C07-04 | `Sources/NativeHACore/Models.swift` | Decode optional server `unit_system.temperature` and `unit_system.length`; pressure, precipitation, visibility, and wind fallbacks derive from length exactly as `getWeatherUnit` does. This is received config, not `AppConfig`. |
| 3 | C07-02–C07-06 | new `Sources/NativeHAMac/WeatherPresentation.swift` | Pure config/current-condition/name/unit/secondary/sentinel presenter and finite weather-only label table. |
| 4 | C07-03 | new `Sources/NativeHAMac/WeatherIconResolver.swift` | Isolated exhaustive HA-condition-to-SF-Symbol mapping and semantic fallback. |
| 5 | C07-05–C07-08 | `Sources/NativeHAMac/CardViews.swift` | Replace the static weather button with responsive semantic rendering and bounded details action. |
| 6 | all active contracts | existing/new tests listed below | Add deterministic coverage, including reference-parity sentinel action behavior. |

Permitted test paths are `Tests/NativeHACoreTests/LovelaceModelTests.swift`, `Tests/NativeHAMacTests/LovelacePresentationTests.swift`, new `WeatherPresentationTests.swift`, `WeatherIconResolverTests.swift`, `WeatherCardIntegrationTests.swift`, `WeatherCardRenderingTests.swift`, and `WeatherCardPerformanceTests.swift`; existing shared lifecycle/GUI tests may be extended only where a cross-module regression is proved. Fixture PNGs remain in `.build/render-artifacts/`; only manually approved OS-labelled baselines may enter `Tests/NativeHAMacTests/ReferenceImages/`.

Do **not** edit `HomeAssistantWebSocketClient.swift`, `HomeAssistantWebSocketConnection.swift`, `DashboardViewModel.swift`, `DashboardHistoryCoordinator.swift`, `DashboardLifecycle.swift`, `LovelaceViewNavigation.swift`, `AppConfig.swift`, or graph renderer files in this milestone. Encountering a need to do so is a stop-and-review condition.

## Validation matrix

### Unit and integration

- Decode/project every weather field including false/zero/empty/structured and malformed cases while preserving raw config and exact identity.
- Exhaustive condition icon/label table; unknown/raw fallback; integer, double, accepted numeric string, null, absent, and malformed attribute matrices.
- Unit precedence and Celsius/Fahrenheit/live-unit fixtures; rounding and secondary-attribute precedence; all four show-flag combinations.
- Missing/unknown/unavailable and action/focus matrix proving the missing entity is non-actionable while both sentinels preserve actions; explicit more-info target override; malformed and unsupported action no-fallthrough; two cards using the same entity retain separate Module 04 identity while sharing accepted global state.
- Assert no `weather/subscribe_forecast` command, task, owner, or persistence write during startup, updates, navigation, refresh, reconnect, stop, or deinit. Modules 02/01/04/12/05/06 focused gates stay green.

### Lifecycle, performance, migration, release

- Repeated 500-state cold presenter and warmed update measurements use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, build fixtures outside measured blocks, consume results, and use stored baselines rather than a new arbitrary millisecond promise.
- Repeated view switches/refreshes demonstrate zero forecast owners and stable weather view identity. Weak-release evidence proves no weather retention.
- Migration test is explicit no-op: no settings, preference, cache, credential, token, profile, or bootstrap migration is introduced.
- `swift test`, macOS 12 release build, `git diff --check`, Module 07 checker, resolver self-test, and applicable inherited-module checkers pass.

### GUI/manual/accessibility

- At display scale 2 and fixed dark-Aqua/locale/timezone, capture `496x150` and `320x190` for sunny, cloudy, rainy, clear-night, missing, unknown, unavailable, missing attributes, Celsius, and Fahrenheit. Assert PNG signature/dimensions/nonblank and semantic regions before comparison.
- Manually compare the same state/config with pinned hass-frontend or the live frontend. Verify clipping, VoiceOver label/value, focus order, Space/Return, the reference-parity sentinel action behavior, and exact default and overridden details targets. Screenshot resemblance is not evidence of units, action routing, lifecycle, or performance.
- No animation is in scope; deterministic state transitions replace keyframes.

### Read-only live smoke

Authorized read-only inspection on 2026-09-05 found server `2026.5.4`, language `en`, timezone `Asia/Shanghai`, weather component loaded, and exactly one entity `weather.forecast_wo_de_jia`. It reported `partlycloudy`, temperature `22.3 °C`, humidity `78`, pressure `1010.5 hPa`, wind `10.8 km/h` bearing `2.8`, and feature bits `3` (daily + hourly). Exactly three raw cards exist in `default_view`, `home_3h`, and `home_12h`; each is `{type, entity, show_forecast:false}`.

A read-only WebSocket subscribe/unsubscribe probe confirmed six daily and 48 hourly forecast entries and exact successful cancellation. This validates the future endpoint only; it does not activate C07-09/10. Release smoke rechecks current state/config before and after reconnect, confirms one visible Home weather card, correct current units/condition, no forecast command, and no state or config mutation. No HA service call is permitted.

## Resolved questions, risks, and stop rules

Resolved: current conditions are the first deliverable; forecast implementation is deferred; implicit secondary is humidity without forecast; server units are runtime bootstrap data; card identity remains Module 04 exact identity; current state remains global Module 05 state; details is the only supported action; an explicit more-info target overrides the card entity; malformed/unsupported actions never fall through to default details; and there is no profile/persistence/migration work. The C07-06 sentinel decision is resolved: `unknown` and `unavailable` preserve the normal action matrix and may open details, while a missing entity remains non-actionable.

Remaining risks are non-blocking for this milestone: SF Symbols approximate MDI; structured names deliberately retain raw data but use the explicit C07-01 fallback until a metadata-capable shared resolver is in scope; and integrations may omit or encode attributes differently. Each has a raw/diagnostic fallback and deterministic test.

Stop and ask before changing observable action semantics beyond C07-06/07, adding an `AppConfig` surface/settings/persistence, changing fixed-server token bootstrap, adding a fetch/subscription/cache/owner, altering Module 02/05/12 lifecycle, using hashes/revisions/timestamps for freshness, expanding generic localization, supporting a non-`en` deployment, or implementing forecast UI.

## Exact handoff

The next action is a fresh Module 07 current-conditions implementer. Run the Module 07 checker and resolver, read this packet and cited anchors, implement C07-01 through C07-08 and C07-11 in the listed order and permitted files, then set this packet to `verification-ready` with the exact diff/tests/artifacts. Do not implement C07-09/10; their only current test is zero forecast ownership. A separate read-only verifier must return GO before the module becomes complete or Module 08 begins.

## Change log

- 2026-09-07: user selected hass-frontend parity for C07-06. Both `unknown` and `unavailable` preserve the normal action matrix; missing remains non-actionable. Packet returned to `research-ready` with no material question unresolved.
- 2026-09-06: fresh audit corrected current/secondary number formatting, unit spacing, explicit missing/null and wind fallbacks, action-target/no-fallthrough semantics, and identified the sentinel action decision for user resolution.
- 2026-09-05: contract revision 1 drafted the bounded current-condition milestone, deferred forecast behavior/ownership, and added read-only live evidence and validation planning.
