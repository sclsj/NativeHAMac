# Module 11 - FanDetailContent Speed, Preset, Direction, and Oscillation Support

## Purpose

Make fan detail controls reflect HA fan capabilities instead of fixed Off/Low/Medium/High speed buttons.

The live server includes `fan.ac_unit_controller_ac_fan`, so this module should focus on percentage-based fans, preset modes, and capability-driven controls.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `FanDetailContent` uses hardcoded speed presets: Off, Low, Medium, High.
- Percentages are fixed at 0, 33, 66, and 100 rather than derived from HA `percentage_step`.
- Preset modes are not fully supported.
- Direction and oscillation controls are not modeled.
- Supported feature flags are not used comprehensively.
- Disabled behavior for unavailable/missing fan entities is limited.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- Fan service calls are owned by the broad dashboard view model rather than a fan-specific controller.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/data/fan.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-fan-speed-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-fan-preset-modes-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-fan-direction-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-fan-oscillate-card-feature.ts`

## Target Architecture

Add fan-specific helpers:

- `FanEntity`
  - Typed wrapper around `HAEntityState`.
  - Parses `percentage`, `percentage_step`, `preset_mode`, `preset_modes`, `direction`, `oscillating`, and `supported_features`.
- `FanFeatureResolver`
  - Decides whether to show speed buttons, speed slider, presets, direction, and oscillation controls.
- `FanServiceController`
  - Builds service payloads for:
    - `fan.turn_on`
    - `fan.turn_off`
    - `fan.set_percentage`
    - `fan.set_preset_mode`
    - `fan.set_direction`
    - `fan.oscillate`

## Confirmed Corrections to Claude's Original Direction

- Do not hardcode Low/Medium/High percentages. HA frontend derives speed control from `percentage_step`.
- Do not show a small fixed set of speed buttons for every fan. HA shows button-style control only when the speed count is small enough; otherwise slider behavior is more appropriate.
- Do not assume presets exist. Use `preset_modes`.

## Implementation Tasks

1. Create typed fan attribute parsing.
   - `percentage`
   - `percentage_step`
   - `preset_mode`
   - `preset_modes`
   - `direction`
   - `oscillating`
   - `supported_features`

2. Decode fan supported features.
   - Mirror HA fan feature constants.
   - Use feature flags to decide whether speed, preset, direction, and oscillation controls should exist.
   - Treat missing feature flags conservatively.

3. Derive speed controls from `percentage_step`.
   - Compute speed count as HA does: roughly `100 / percentage_step`.
   - If the count is small enough, show discrete buttons.
   - If the count is larger, show a percentage slider/stepper.
   - Always include off behavior separately from nonzero percentage when appropriate.

4. Implement correct percentage service payloads.
   - `fan.set_percentage` with `percentage`.
   - Clamp to `0...100`.
   - Snap to valid step increments.
   - Use `fan.turn_off` for off if that matches existing service semantics better than setting 0.

5. Add preset mode support.
   - Show presets from `preset_modes`.
   - Use exact preset strings in service calls.
   - Format labels only for display.

6. Add direction and oscillation controls.
   - Direction should use HA-supported direction values where present.
   - Oscillation should send boolean payload through `fan.oscillate`.

7. Add disabled/error states.
   - Missing entity: show a clear unavailable detail view.
   - `unavailable`/`unknown`: display current state and disable mutating controls.
   - Service failure: show a nonfatal error and wait for actual HA state to confirm changes.

8. Move fan service construction out of `DashboardViewModel`.
   - Keep public view-model methods as wrappers if needed during migration.
   - The service controller should be directly testable.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/FanEntity.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/FanFeatureResolver.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/FanServiceController.swift`

Out of scope:

- Inferring fan relationships from climate entities.
- Custom fan visualizations.
- Full HA more-info dialog parity.

## Tests and Verification

Follow the shared macOS 12 method in [`../visual-testing.md`](../visual-testing.md). Default tests must use fixed `HAState` fixtures and a recording service boundary; do not connect to HA or load real credentials.

Likely tests belong in the existing `NativeHAMacTests` target:

- `Tests/NativeHAMacTests/FanEntityTests.swift`
- `Tests/NativeHAMacTests/FanServiceControllerTests.swift`
- `Tests/NativeHAMacTests/FanDetailInteractionTests.swift`
- `Tests/NativeHAMacTests/FanDetailRenderingTests.swift` (or the existing `GUIRenderingAndPerformanceTests.swift` while its renderer remains shared)

### Unit tests

Use complete and sparse fixtures modeled on `fan.ac_unit_controller_ac_fan`, with a fixed `last_changed`. Cover off; on at 1%, 25%, 33%, 50%, 66%, and 100%; unavailable; unknown; on with no `percentage`; small and large `percentage_step`; preset-only; and full preset/direction/oscillation capabilities.

Test:

- typed parsing of percentage, step, preset, direction, oscillation, and supported features, including missing and wrong-type values;
- decoding each `FanEntityFeature` bit and capability combinations;
- the hass-frontend speed-count contract `round(100 / percentage_step) + 1`, including the typed `AppConfig` button/control threshold (reference default: four speeds) and slider behavior above it;
- percentage-to-discrete-speed and discrete-speed-to-percentage mapping where buttons apply;
- percentage clamping, step snapping, rounding ties, missing/zero/invalid steps, and off behavior;
- exact payloads for set percentage, preset, direction, oscillation, turn on, and turn off, including preservation of raw preset/direction strings;
- disabled/rejected actions for missing, unavailable, and unknown entities; and
- optimistic request, matching confirmation, differing authoritative update, failure/rollback, and stale-response ordering.

The functions, feature constants, `FAN_SPEED_COUNT_MAX_FOR_BUTTONS`, and service behavior in `/Users/jin/Documents/HA/hass-frontend/src/data/fan.ts` and `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-fan-speed-card-feature.ts` are semantic reference contracts. Do not rely on a screenshot for them. If a contract test is added before its fix, use only a narrowly scoped, reasoned `XCTExpectFailure` and remove it as part of this module.

### Integration tests

Run these tests on the main actor because they touch `DashboardViewModel` and SwiftUI state. Drive `FanDetailContent` or `EntityDetailSheet` with a `DashboardViewModel` and fake/recording `FanServiceController`. Verify that:

- off and each supported on percentage select/display the correct state;
- a small speed count uses capability-derived discrete controls, while many levels use the percentage control;
- missing percentage has a safe intentional display and does not fabricate a selected speed;
- presets, direction, and oscillation appear only when reported, can coexist when all are supported, and send exactly one correctly shaped action;
- unavailable/unknown/missing entities cannot mutate HA state;
- the optimistic selection waits for realtime confirmation, authoritative HA state wins on disagreement, and a service error restores a truthful UI; and
- dismissing detail cancels any history/subscription or animation work owned by the view.

Test service-call count and payloads directly; a selected button in a PNG does not prove that the correct HA action was sent.

### GUI rendering and visual regression

Run GUI tests on the main actor. NativeHA targets macOS 12 with Swift 5.6/Xcode 13.4.1, so do not propose SwiftUI `ImageRenderer`. Reuse the proven offscreen AppKit harness: `NSHostingView` inside a small `NSWindow`, captured using `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`.

Render the complete detail at `520x620` points and use `360x620` for one narrow-content/control-layout case. Use display scale 2, dark Aqua/dark color scheme, fixed timestamps, and fixed locale/timezone where production APIs permit. The current `EntityDetailSheet` is fixed at 520 points; unless this module intentionally makes it adaptive, the narrow fixture should host `FanDetailContent` rather than claim that the sheet already supports a narrow width.

Always write PNGs to `.build/render-artifacts/` for:

- off;
- on at a low, middle, and 100% percentage (use 25%, 50%, and 100% for a slider fixture, plus the exact supported values for a discrete-step fixture);
- unavailable;
- on with percentage missing;
- a small-step-count discrete-button configuration;
- a many-step slider configuration; and
- supported preset/direction/oscillation combinations, including the normal and narrow layouts.

Use stable names such as `fan-detail-on-50-520x620.png` and `fan-detail-capabilities-360x620.png`. First verify the PNG signature, exact dimensions, nonblank output, expected control/content regions and selected-state color family, and settlement past any asynchronous loading state. These are lightweight renderer checks, not evidence of value mapping or lifecycle correctness.

Compare artifacts with the equivalent fixture in `/Users/jin/Documents/HA/hass-frontend` or the live frontend before copying an approved PNG into `Tests/NativeHAMacTests/ReferenceImages/`. Never approve current NativeHA output mechanically. Keep approved baselines tied to a documented macOS version and compare tolerantly for antialiasing differences. Intentional changes require review of actual, expected, and preferably diff artifacts before updating a baseline. CI may set `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1` only when the approved set is complete.

### Animation and interaction

The currently confirmed `FanDetailContent` is static, and custom fan visualizations remain out of scope, so no rotating-fan animation snapshot is required by default. Do use explicit state snapshots for off and supported percentage selections rather than trying to automate a trackpad gesture nondeterministically.

If implementation introduces a rotating icon, progress interpolation, pressed/hover transition, or other substantive animation, expose deterministic animation phase/progress. Render at least start, midpoint, and end (`0`, `0.5`, `1`) to stably named `.build/render-artifacts/fan-detail-animation-*.png` files, assert distinct keyframes and that the final keyframe equals the direct final state, and add pure interpolation/clamping tests. Also verify reduced-motion behavior if supported and prove the animation clock/task stops when detail is hidden. Use bounded settlement expectations, not long sleeps or scheduler timing.

For any slider/drag control, add pure location-to-percentage, clamping, and step-rounding tests plus explicit untouched, dragging, optimistic, confirmed, and rejected states. True input-event-to-frame/hitch automation is deferred to a future XCUITest target on newer Xcode.

### Performance and lifecycle

Use the Xcode 13.4.1-compatible `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, not `XCTHitchMetric`. Prefer stored XCTest baselines; any hard ceiling must be deliberately loose and documented. Construct fixtures outside the measured block, warm caches before warm paths, and consume each measured result.

Separate measurements for:

- cold parsing/feature/control preparation of 10,000 fan states spanning step and capability combinations;
- cold initial `520x620` detail construction/rendering;
- warm mapping and selection updates for 10,000 fixed percentage changes;
- 1,000 repeated realtime state updates and optimistic reconciliations;
- a continuous 1,000-location slider gesture if the slider is implemented, measured separately from bitmap rendering and paired with an assertion that service calls are committed/coalesced as designed; and
- 100 detail open/close cycles, followed by cancellation, weak-reference, and memory checks for history subscriptions, callbacks, controllers, render tasks, and any animation clock/task.

If an animation exists, compare hidden versus visible repeated-update work and assert that hidden detail performs no animation-frame production. Signpost metrics apply only if production code has meaningful instrumentation. Do not combine parsing/controller throughput and offscreen bitmap creation into one number.

### Manual QA and current limits

- Open `fan.ac_unit_controller_ac_fan` and compare the controls side-by-side with hass-frontend.
- Confirm displayed controls match `percentage_step`, `supported_features`, `preset_modes`, direction, and oscillation; test off and several live percentages.
- Inspect the actual service calls and confirm the UI waits for realtime confirmation or reconciles a failure/external change truthfully.
- Repeatedly open/close detail and switch away; confirm no hidden animation, graph render, or subscription work continues.
- Inspect normal/narrow clipping, selected-state contrast, long preset labels, focus/keyboard behavior, and control hit regions.

Offscreen PNGs cannot prove percentage correctness, accessibility, payload semantics, lifecycle cleanup, smooth animation, or performance. Xcode 13.4.1 lacks `XCTHitchMetric`; real pointer/trackpad event-to-frame and launch tests remain manual or future XCUITest work under newer Xcode.

## Dependencies

- Module 05 for service controller extraction and error handling.
- Module 06 for shared state display and disabled-state conventions.

## Risks

- Some integrations expose both percentage and presets in ways that are mutually exclusive. UI should show both only if HA attributes support both.
- Setting percentage to 0 versus calling `turn_off` can differ by integration. Prefer HA frontend semantics and test against live fan behavior carefully.
- Feature constants must stay aligned with HA.
- A missing percentage while state is `on` must not silently look like off; semantic state tests and a dedicated visual fixture are required.
- Step rounding can drift from hass-frontend if implemented independently. Keep the local reference functions under conformance tests, and verify that the configurable button threshold defaults to the reference value.
- Service-call coalescing, optimistic confirmation, and out-of-order state updates can cause flicker or call storms even when static snapshots look correct.
- Any repeating fan animation can retain a task or consume CPU after the detail disappears unless its lifetime is explicit and tested.
- Baselines vary with macOS font/control rendering. Fixed scale, appearance, timestamp, locale/timezone, and a documented OS baseline reduce noise but do not validate control semantics.

## Acceptance Criteria

- Fan speeds are derived from HA `percentage_step`, not hardcoded.
- Preset, direction, and oscillation controls are capability-driven.
- Fan service payloads are centralized and tested.
- Unavailable/missing fans have intentional disabled UI.
- The live fan remains controllable without personal hardcoded assumptions.
- Complete, sparse, unavailable, missing-percentage, small-step, large-step, and full-capability fixtures pass parsing, feature, value mapping, rounding, payload, and optimistic-reconciliation tests offline.
- Semantic tests match hass-frontend's speed-count and percentage conversion behavior, the typed button-threshold policy defaults to the reference value, and service spy tests prove the exact action count and payload for speed, preset, direction, oscillation, on, and off.
- Valid, nonblank `520x620` and narrow `360x620` PNG artifacts cover off, several on percentages, unavailable, missing percentage, discrete controls, slider controls, and supported preset/direction/oscillation combinations; checked-in references are manually approved against hass-frontend on a documented macOS version and pass tolerant comparison.
- If animation or a gesture-driven progress control is implemented, deterministic keyframes and pure gesture/value tests pass, reduced motion is covered where supported, and hidden detail performs no animation work. No animation-only test is required for an intentionally static implementation.
- Stored performance measurements cover cold preparation/rendering, warm 10,000-update mapping, repeated realtime reconciliation, and 100 open/close cycles without retained subscriptions, callbacks, render tasks, controllers, or animation resources.
- The full module test set passes on macOS 12 with Swift 5.6/Xcode 13.4.1 without `ImageRenderer`, `XCTHitchMetric`, network access, live credentials, or live HA state.
- Manual QA confirms live percentage/preset/mode behavior, focus and layout at the intended widths, and absence of hidden work; later XCUITest/hitch work is documented rather than claimed complete.
