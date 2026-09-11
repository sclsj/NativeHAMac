# NativeHA Rescue Plan Index

This directory contains staged implementation plans. Their original findings are historical; current scope/status comes from the evidence packets, approved product decisions, and fresh audits. The reference implementation is `/Users/jin/Documents/HA/hass-frontend`.

## Current Readiness

The [2026-09-11 readiness audit](../audits/2026-09-11-readiness.md), against `adc2c03`, found substantial rescue progress plus four bounded findings. The user's follow-up changes their priority:

- **A4 bootstrap duplication:** repaired and validated. Production and fixture bootstrap entry points now use the same `runOwnedBootstrap` lifecycle; the follow-up validation is recorded in the audit.
- **A1 climate fallback crash and A2 numeric-axis nontermination:** deferred. Both were reproduced with synthetic inputs; reachability from the deployed Home Assistant server was not established. Deferral does not close them or assert that HA cannot supply the triggering data.
- **A3 graph step/hover/viewport semantics and false-positive step test:** deferred to a dedicated graphing module alongside further user-requested changes. Re-scope that module before implementing it.

The deferred findings are no longer a gate on the next feature. Preserve the narrower verified transport/history/weather contracts; green tests or source hashes alone do not establish whole-app parity.

- Modules 02, 01, and 04 are complete and independently green. Their evidence packets are the implementation authority for transport, history/feed/render ownership, and exact Lovelace view/card identity.
- Module 03 is intentionally skipped, not complete. NativeHA targets one fixed personal deployment and keeps the existing token/bootstrap path without a profile store, switching, migration, or settings UI.
- Module 12 is complete and independently re-verified at contract revision 1. Preserve its exact view/card identity, fixed-server navigation persistence, one-tail owner reconciliation, and accessibility contracts in later work.
- Modules 05 and 06 are complete and independently verified under the fixed- server assumption. Module 06 preserves source-row identity, implements the bounded row presentation/action/power matrix, carries already-fetched registry `ic` without a new command, and adds no owner, fetch, cache, persistence key, or typed configuration surface.
- Module 07 revisions 1 and 2 are complete and independently verified. Under C07-12 through C07-18, activating weather opens the specialized current/ measurement/forecast detail with exactly one selected-detail forecast owner. C07-09/10 dashboard-card forecast remains deferred; mounted `show_forecast:false` cards still own nothing.
- The bounded Module 09 async repair remains correct, green, and separate from broader Module 09. A known stale-viewport request can still cause repeated safe off-main alignment/full-preparation fallback. Do not suppress it using numeric ordering of content hashes or endpoint timestamps; a future bounded repair needs coordinator-owned revision provenance.

## Module Order

Implement in this order unless a future audit finds a blocker:

1. Modules 02, 01, and 04: complete and green.
2. Module 03: intentionally skipped under the fixed-deployment deviation.
3. Module 12: complete and independently re-verified.
4. Module 05: complete and independently verified under the fixed-server assumption.
5. Module 06: complete and independently verified at contract revision 2.
6. Module 07 revision 1 current conditions: complete and independently verified.
7. Module 07 revision 2 weather more-info: complete and independently verified; keep C07-09/10 dashboard forecast deferred.
8. A4 bootstrap consolidation and lifecycle validation are complete. Keep A1/A2 deferred and collect A3 into the future dedicated graphing module; do not repair or redesign graphs as part of this cleanup.
9. Module 08 is the next research gate. Its plan now corrects marker-free server rendering, source-versus-rendered empty content, and existing decoder status, but it still needs a complete researched and independently reviewed packet. Module 08 implementation follows that review, not the deferred audit fixes.

Later subscription consumers reuse completed Module 02. Preserve the coordinated Module 01/12 graph-range and active-owner contracts.

## Dependency Map

| Module | Area | Depends On | Blocks |
|---|---|---|---|
| 01 | History `history/stream` | 02, partly 04 | 05, 09, detail history |
| 02 | WebSocket multiplexer | none | 01, 07 forecast, 08 templates |
| 03 | Server profiles | intentionally skipped; fixed personal deployment | none |
| 04 | Lovelace decode robustness | 02 for fetch path only | 01, 05, 06, 07, 08, 12 |
| 05 | DashboardViewModel orchestration | 01, 02, 04, 12 | Card behavior consistency |
| 06 | Entities/entity rows | 04, 05 | Current dashboard row correctness |
| 07 | Weather card | 02, 04, 05 | Forecast subscription later |
| 08 | Markdown card | 02, 04, 05, 12 routing | Template/render lifecycle parity |
| 09 | Graph rendering | 01, 05 | History visual parity |
| 10 | Climate detail | 05, 06 | More-info climate correctness |
| 11 | Fan detail | 05, 06 | More-info fan correctness |
| 12 | Lovelace views/sidebar | 04, partly 01 | Dashboard navigation correctness |

## Live Dashboard Scope

The recorded live server surface informs prioritization before broad Home Assistant coverage; these counts and states are historical observations, not a fresh live check:

- Three Lovelace views exist: `Home` (`default_view`), `3h` (`home_3h`), `12h` (`home_12h`). The latter two are maintenance workarounds, not intended separate dashboards.
- Flattened card types currently in use: `entities`, `history-graph`, `vertical-stack`, `weather-forecast`, `markdown`.
- Present the intended Home dashboard once and use the typed `AppConfig` time-range policy for the available ranges, default, and selector behavior.
- The default dashboard's `vertical-stack` values are layout workarounds. Preserve their raw config, but render the approved configurable three-column composition.
- Weather cards currently use `show_forecast: false`. Current-state weather display matters before forecast rows.
- Entity surface is mostly sensors, switches, automations, device trackers, binary sensors, weather, `climate.room_ac`, and `fan.ac_unit_controller_ac_fan`.

## Historical corrections retained by the rescue

- Do not generally remove `unknown`, `unavailable`, or `none` from history ingestion. The hass-frontend timeline path keeps these as timeline states with distinct colors. Numeric line graph preparation can skip nonnumeric samples in the line-only path.
- Module 01 required Module 02's single receive loop and ID-based dispatch; both are now implemented and must be preserved.
- Keep one configurable graph-range selector on the intended Home dashboard instead of exposing the duplicate `3h` and `12h` maintenance views as separate dashboards.
- Keep approved product, layout, interaction, scheduling, sampling, and cache choices as typed policies in `AppConfig.swift`; the fixed server/token bootstrap remains the explicitly approved personal-deployment exception.
- Weather current-card display and modal forecasts are complete. Keep dashboard-card forecasts deferred under C07-09/10; preserve the one selected-detail forecast owner.
- Preserve the bounded graph async-repair contracts. The broader graph scope and architecture will be revisited in the dedicated user-requested module; this index does not preselect that design.

## Reference Anchors

Primary hass-frontend files cited by the module plans:

- History and stream semantics: `/Users/jin/Documents/HA/hass-frontend/src/data/history.ts`
- History graph card: `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-history-graph-card.ts`
- Timeline chart/color: `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-timeline.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/timeline-color.ts`
- Line chart behavior: `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line-data.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/state-history-chart-line.ts`, `/Users/jin/Documents/HA/hass-frontend/src/components/chart/ha-chart-base.ts`
- Entity display/icons/toggle: `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/entity/state_icon.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/entity/can_toggle_domain.ts`, `/Users/jin/Documents/HA/hass-frontend/src/common/const.ts`
- Weather: `/Users/jin/Documents/HA/hass-frontend/src/data/weather.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-weather-forecast-card.ts`
- Markdown: `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-markdown-card.ts`
- Lovelace models/views: `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/*.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts`, `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/views/hui-view.ts`

## Shared Testing Method

Use [`../visual-testing.md`](../visual-testing.md) for the macOS 12/Xcode 13.4.1 rendering harness, artifact approval workflow, performance-metric availability, and current-machine limits. Each module plan below adds the fixtures, sizes, states, interactions, lifecycle checks, and pass conditions specific to that module.

Keep the test layers distinct:

- Pure/core tests in `NativeHACoreTests` prove decoding, formatting, geometry, state machines, and reference-frontend semantic contracts without AppKit or network access.
- `@MainActor` offscreen GUI tests in `NativeHAMacTests` host SwiftUI in `NSHostingView` and capture through `bitmapImageRepForCachingDisplay(in:)` plus `cacheDisplay(in:to:)`; SwiftUI `ImageRenderer` is unavailable at the macOS 12/Swift 5.6 deployment level.
- Every GUI test writes a current PNG to `.build/render-artifacts/` and first checks signature, dimensions, nonblank content, expected regions/colors, and settled asynchronous state. An approved, macOS-version-labelled image belongs in `Tests/NativeHAMacTests/ReferenceImages/` only after manual comparison with `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend; tolerant pixel comparison may then enforce it. Do not approve current NativeHA output mechanically.
- XCTest performance coverage uses `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, separates cold preparation from warmed interaction/update work, constructs fixtures outside measured blocks, and consumes measured results. Prefer stored baselines to machine-sensitive millisecond limits.
- True launch, accessibility traversal, event-to-frame hitch, trackpad/scroll deceleration, and end-to-end input timing remain later XCUITest work under a newer Xcode app target. Xcode 13.4.1 has no `XCTHitchMetric`; module completion must not depend on that unavailable API.

Default tests use fixed timestamps, appearance, logical sizes, display scale, color scheme, and—where the production API permits—locale/timezone. They do not use live Home Assistant state, credentials, or network access. Temporary `XCTExpectFailure` is acceptable only for a narrowly identified hass-frontend conformance gap, with a reason and removal required by the implementation that fixes it.
