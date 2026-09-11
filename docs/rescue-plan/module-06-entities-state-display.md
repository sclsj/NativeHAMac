# Module 06 - EntitiesCard, EntityRow, State Display, and Entity Icons

> **Status: complete within the verified packet scope.** The
> [Module 06 evidence packet](../reference-context/modules/module-06-entities-state-display.md)
> records implemented contracts, validation, and deferred work. The original
> findings, architecture sketches, task lists, and acceptance checklist below
> are historical planning, not a fresh code audit or remaining-work checklist.
> Preserve the packet contracts; verify current code before reopening work.

## Purpose

Make `entities` cards feel like Home Assistant instead of a basic list of strings. This module covers state display, entity names, icons, missing entities, toggle behavior, row options, and secondary information.

The live dashboard has 12 `entities` cards, so this module has high user-visible impact.

## Historical Findings Before Rescue

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `EntitiesCard` renders a title and rows, but supports only a small subset of HA entity-row behavior.
- Header toggle behavior is based on `toggleable.count > 1`; it does not honor Lovelace `show_header_toggle`, nor does it match HA's default behavior closely.
- `EntityRow` shows a simple icon, display name, display state, and optional toggle button.
- Missing entities are not treated as first-class row states.
- Row-level options such as `name`, `icon`, `secondary_info`, `type`, `tap_action`, and `hold_action` are not modeled robustly.
- Toggleability is delegated to `DashboardViewModel.canToggle`, which recognizes only `switch`, `fan`, `input_boolean`, and `automation`.
- `DomainIcon` covers only a small set of domains and does not account for state, device class, or special cases.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- `displayState(for:)` is simple numeric formatting plus unit plus underscore replacement.
- `displayName(for:)` falls back to the entity ID suffix with underscores replaced.
- Domain parsing is duplicated instead of centralized.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-entities-card.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/components/hui-generic-entity-row.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/entity-rows/hui-simple-entity-row.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/entity-rows/hui-toggle-entity-row.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_name.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/state_icon.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/can_toggle_domain.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/device_tracker_icon.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/update_icon.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/const.ts`

## Target Architecture

Add shared entity presentation helpers:

- `EntityDisplayFormatter`
  - Formats state values, units, timestamps, durations, percentages, and unavailable states.
  - Uses entity domain, device class, state class, unit, and relevant attributes.
- `EntityNameResolver`
  - Applies row `name` override first.
  - Falls back to friendly name.
  - Falls back to HA-like entity ID cleanup.
- `EntityIconResolver`
  - Applies row `icon` override first.
  - Uses domain, state, device class, and attributes.
  - Returns SF Symbols initially, but keeps a clean mapping boundary if Material Design Icons are added later.
- `EntityActionResolver`
  - Determines whether an entity can be toggled.
  - Knows domain-level toggle support and unavailable/missing state.
  - Does not make service calls directly.

## Confirmed Corrections to Claude's Original Direction

- Do not implement state display by excluding `unknown`, `unavailable`, or `none` globally. For entity rows, those should display clearly as unavailable/unknown states.
- Do not place hardcoded personal display names or personal entity hiding in `EntitiesCard`. That belongs in the approved typed `AppConfig` presentation policy.
- Do not broaden toggle behavior only by adding domains. Toggle must also account for entity availability and service support where possible.

## Implementation Tasks

1. Expand Lovelace entity-row decoding through Module 04.
   - Support string rows and dictionary rows.
   - Preserve `entity`, `name`, `icon`, `type`, `secondary_info`, `tap_action`, `hold_action`, `double_tap_action`, and `state_color`.
   - Keep unknown row fields in an extras dictionary for future modules.

2. Implement `EntityDisplayFormatter`.
   - Numeric state plus `unit_of_measurement`.
   - State string localization/friendly cleanup.
   - `unknown`, `unavailable`, and missing entity display.
   - Device tracker home/not_home display.
   - Battery, humidity, temperature, pressure, signal strength, timestamp, date, duration, enum, and monetary device-class basics.
   - Preserve raw state where no known rule applies.

3. Implement row name resolution.
   - Preserve exact string names, including empty; use the packet C06-03 structured-name matrix.
   - Then use `attributes.friendly_name` with the packet null/scalar semantics.
   - Otherwise replace underscores in the object ID with spaces, without title-casing.

4. Implement icon resolution.
   - Precedence is row `icon`, already-fetched registry `ic`, state `attributes.icon`, then state/device-class/domain fallback (C06-05); add no icon fetch.
   - Domain-based fallback should cover live domains: `sensor`, `automation`, `switch`, `device_tracker`, `button`, `binary_sensor`, `zone`, `number`, `script`, `select`, `update`, `climate`, `fan`, and `weather`.
   - Add state-aware cases for binary sensors, device trackers, switches, automations, updates, covers if added later, and weather if shown in entity rows.

5. Implement toggle eligibility.
   - Keep implicit row selection, header candidate eligibility, and actual service routing separate under C06-07. `DOMAINS_TOGGLE` alone is not the row/control matrix.
   - Include `fan` percentage support through Module 11 where appropriate.
   - Disable toggles for missing, `unavailable`, and unknown entities.
   - Use the verified static route matrix and installed-caller/lifetime gates; add no service-catalog fetch in this scope.

6. Fix header toggle behavior.
   - Decode and honor `show_header_toggle`.
   - Use C06-07 exactly: when title is present (including empty) and `show_header_toggle` is absent, require two configured entity rows in `DOMAINS_TOGGLE`; otherwise Boolean-coerce the explicit flag. Actual candidates, checked state, and safe dispatch are separate decisions.
   - Header toggle should call service only for entities currently eligible for toggle.

7. Add secondary information support.
   - Preserve the C06-09 supported matrix: `entity-id`, `last-changed`, `last-updated`, `last-triggered`, `position`, `tilt-position`, `brightness`, and `state`; do not treat arbitrary attribute names as supported.
   - Format timestamps using the app timezone/locale.
   - Keep unsupported values visually absent rather than showing raw config.

8. Add missing entity row state.
   - Render the row with a warning icon and a clear missing-state label.
   - Do not crash when Lovelace references an entity not returned by `/api/states`.

9. Keep action support conservative.
   - `tap_action`, `hold_action`, and `double_tap_action` should be decoded now.
   - Implement only existing app-supported actions in this module.
   - Preserve C06-08: absent tap and supported `more-info` route to details, `none` suppresses activation, and safe `toggle` uses the existing service owner. Unsupported tap/hold/double actions remain visible diagnostics and never fall through.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/EntityDisplayFormatter.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/EntityIconResolver.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/EntityActionResolver.swift`

Out of scope:

- Full Material Design Icon rendering.
- Full HA translation catalogs.
- Editing Lovelace entity rows.
- Service-call protocol changes beyond using existing toggle hooks.

## Tests and Verification

Follow the shared macOS 12 capture and baseline workflow in [`../visual-testing.md`](../visual-testing.md). Keep formatting, action eligibility, and state-color rules under semantic test even when the same fixture also has a PNG; a screenshot cannot establish that the underlying value or service target is correct.

### Unit tests

In the `NativeHAMacTests` target, add `EntityDisplayFormatterTests.swift`, `EntityIconResolverTests.swift`, and `EntityActionResolverTests.swift`. Use fixed entity timestamps, an `en_US_POSIX` locale, and an explicit timezone for timestamp and secondary-info expectations. Cover:

- row-name precedence (`name`, `friendly_name`, then cleaned entity ID), long names, and the optional entity-ID line;
- numeric state plus unit, string-state cleanup, and representative temperature, humidity, battery, timestamp, duration, and device-tracker formatting;
- distinct `unknown`, `unavailable`, and missing-entity presentation data;
- row icon override, domain/device-class/state icon resolution, and `state_color` decisions for on/off and unavailable states;
- toggle eligibility by domain, availability, and capability; header-toggle defaulting and explicit `show_header_toggle`; and the exact eligible entity IDs passed to single-row and header toggle actions;
- secondary-info selection and timestamp formatting; and
- stable row identity when two configured rows refer to the same entity with different row options.

Where hass-frontend defines the contract, derive expected behavior from `hui-entities-card.ts`, the entity-row implementations, and the `compute_state_*` and `state_icon.ts` references listed above. Do not use a pixel baseline to replace these assertions.

### Integration tests

Add `EntitiesCardIntegrationTests.swift` in `NativeHAMacTests`. Drive `EntitiesCard` with a `DashboardViewModel` containing only fixture states; do not use REST, WebSocket, credentials, or a live Home Assistant server. Verify that a burst update changes only the intended row, entity-ID visibility updates layout without changing the presented value, unavailable/missing rows do not invoke services, and row/header toggle bindings issue the intended action once. Also verify that removing or replacing the card releases any observation or task introduced by this module.

### GUI rendering and visual regression

Add focused cases to `EntitiesCardRenderingTests.swift` (or keep them in the existing `GUIRenderingAndPerformanceTests.swift` while the shared renderer lives there). Run the class on the main actor because it creates `NSApplication`, `NSHostingView`, AppKit windows, SwiftUI state, and `DashboardViewModel`. `MacViewPNGRenderer` is the proven pattern: host the view in a small offscreen borderless window, then capture it using `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`. Do not propose SwiftUI `ImageRenderer`; NativeHA targets macOS 12 with Swift 5.6/Xcode 13.4.1.

Render fixed logical sizes at display scale 2 in dark Aqua: the production dashboard width of **496 points** and a narrow **320-point** variant. Use `496x210` and `320x250` for one/two-row state fixtures, `496x270` and `320x330` when the optional entity-ID line is visible, and `496x420` and `320x480` for the mixed-domain fixture. Use stable timestamps, appearance, color scheme, locale, and timezone. Produce inspectable PNGs in `.build/render-artifacts/` for:

- a numeric sensor with a unit;
- separate `unknown` and `unavailable` rows;
- a toggleable entity in both on and off states;
- a long friendly name at both widths;
- a missing entity;
- the same card with entity-ID display off and on; and
- a mixed-domain card containing at least sensor, binary sensor, device tracker, switch, automation, and weather rows.

Use descriptive names that encode fixture and width, for example `entities-numeric-unit-496.png`, `entities-long-name-320.png`, `entities-toggle-on-496.png`, and `entities-mixed-domains-320.png`, so actual, expected, and future diff artifacts cannot be confused.

Before comparison, assert the PNG signature, exact pixel dimensions, nonblank content, and expected rendered regions/color families. Add semantic layout probes where production seams permit them for one-line truncation, consistent row height, icon/state color, divider count/placement, and toggle state. Always write the current artifact. Manually compare it with the same configuration and states in `/Users/jin/Documents/HA/hass-frontend`; do not approve the current NativeHA output mechanically. Only reviewed PNGs belong in `Tests/NativeHAMacTests/ReferenceImages/`, with tolerant pixel comparison and the macOS baseline version documented. A deliberate visual update requires review of actual, expected, and preferably diff artifacts before replacing a baseline; missing approved references may become mandatory later with `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1`.

### Animation and interaction

The current plan does not require a new custom row animation. If implementation retains only the system toggle, test the meaningful on/off and enabled/disabled states instead of trying to advance AppKit's scheduler. If this module adds a custom toggle, hover, or press animation, expose deterministic presentation state and render start, midpoint, and end (normally progress `0`, `0.5`, and `1`) plus hovered/unhovered and pressed/released states. Assert frames are distinct and the last frame matches the stable final state; add pure interpolation/clamping/state-transition tests and reduced-motion behavior where the production API supports it. Avoid long sleeps; use bounded expectations or polling only for UI settlement.

### Performance and lifecycle

Add `EntitiesCardPerformanceTests.swift` in `NativeHAMacTests`. Build fixtures outside each measured block and consume the resulting presentation rows or rendered bitmap. Measure with `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`:

- cold presentation of a 500-row mixed-domain card;
- warm presentation/layout of that card after caches are primed;
- repeated incremental batches that update 100 of 500 entities without rebuilding unrelated row presentation; and
- repeated creation/removal of the card and any observation/task state.

Use stored XCTest baselines rather than tight millisecond limits; any safety ceiling must be deliberately loose and documented. Check that memory returns to a stable range and service callbacks/observers are not retained after the card disappears. Measure formatter/action preparation separately from offscreen PNG capture so AppKit rasterization does not hide a model regression. Signpost metrics apply only if the relevant path is instrumented. `XCTHitchMetric` is not available in Xcode 13.4.1; true click/hover/scroll event-to-frame testing remains later XCUITest work under newer Xcode.

### Manual QA

- Open each live `entities` card and compare labels, units, state-aware icons, dividers, row density, and header-toggle visibility with hass-frontend.
- At normal and narrow window widths, confirm long labels truncate cleanly, optional IDs do not overlap state/toggle controls, and keyboard focus and hover/press feedback remain understandable.
- Confirm missing, unavailable, and unknown entities are intentional and that disabled rows/header toggles cannot issue service calls.
- Confirm no personal entity names are hardcoded in row rendering and no test uses live credentials or server state.

## Dependencies

- Module 04 for robust row config decoding.
- Module 05 for moving display and action logic out of `DashboardViewModel`.
- Approved `AppConfig` presentation policy for hidden entities; Module 03 is intentionally skipped and is not a prerequisite.

## Risks

- Exact HA display localization is large. Start with faithful structural behavior and current-dashboard domains, then expand.
- SF Symbols do not map one-to-one with HA's Material Design Icons. Keep the resolver isolated so the icon backend can change later.
- Header toggle can call many services. Keep it opt-in to eligible entities only and show clear disabled states.
- System toggle drawing, fonts, and antialiasing can differ by macOS release; keep approved references OS-specific and tolerant rather than weakening semantic state/action assertions.
- A 496-point-only snapshot can hide narrow-layout clipping, while a screenshot alone can hide incorrect formatting or service routing. Keep both widths and the semantic contracts above.
- Real-time hover/press animation and event-to-frame hitch automation are not reliable in the current SwiftPM/Xcode 13.4.1 setup; use explicit states now and defer true input automation to a later XCUITest target.

## Acceptance Criteria

- All live `entities` cards render without unsupported row crashes.
- State display is centralized and tested.
- Toggle eligibility is centralized and aligned with HA's domain model for the supported domains.
- Missing, unavailable, and unknown entities are displayed intentionally.
- Row-level `name`, `icon`, and `secondary_info` are honored.
- `DashboardViewModel` no longer contains the primary state-display implementation.
- Unit and integration tests cover formatting/name/icon precedence, unavailable and missing states, header/row toggle eligibility and routing, and isolated burst updates without network access.
- Reviewed 496-point and 320-point artifacts cover the required representative entity states, pass PNG/dimension/nonblank/color-region checks, and use OS-documented tolerant references where approved.
- Row height, truncation, divider placement, icon/state color, optional entity-ID layout, and toggle state have semantic or focused rendering assertions; no acceptance claim relies on screenshots alone.
- The 500-row cold/warm/update measurements and repeated card lifecycle checks pass their stored XCTest baselines without retained observers, tasks, or callbacks.
- Any custom animation added by the implementation has deterministic keyframe and reduced-motion coverage where supported; otherwise stable system-control states are tested explicitly.
