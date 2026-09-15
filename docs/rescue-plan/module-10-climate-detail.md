# Module 10 - ClimateDetailContent Capabilities and Service Semantics

> **Status: complete within the evidence packet's scope.** The [Module 10 evidence packet](../reference-context/modules/module-10-climate-detail.md) defines current detail-specific contracts and corrects historical assumptions below. Audit A1 (recursive fallback when both temperature attributes are absent) is repaired and covered by passing sparse-state regressions. Independent offline/reference verification and explicitly authorized live temperature/preset/HVAC command-reconciliation acceptance passed; original Off/22.8°C/None settings were restored and independently rechecked. Physical compressor operation and real trackpad/hitch behavior were not verified.

## Purpose

Make climate detail controls driven by the entity's actual HA attributes and supported features, instead of prototype defaults and personal configuration.

The live server includes `climate.room_ac`, so this module should focus first on air-conditioner style climate entities before broad thermostat coverage.

## Historical pre-implementation findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `ClimateDetailContent` reads some climate attributes but uses fallback behavior that is not always HA-derived.
- HVAC modes default to a small hardcoded set when attributes are absent.
- Preset target temperatures come from `AppConfig.climatePresetTargetTemperatures`, which is personal configuration rather than HA entity truth.
- A specific fan entity fallback appears in action labeling, tying the climate detail surface to the user's current setup.
- Supported feature flags are not used comprehensively to decide which controls should exist.
- Temperature ranges, target high/low ranges, humidity targets, fan mode, swing mode, preset mode, and auxiliary heat are not fully modeled.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`:

- Climate service calls are part of the broad view model rather than a focused service/controller layer.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift`:

- Climate preset target temperatures are hardcoded in app config.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/data/climate.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-climate-hvac-modes-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-climate-preset-modes-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-climate-fan-modes-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-climate-swing-modes-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/card-features/hui-target-temperature-card-feature.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`

## Target Architecture

Add climate-specific helpers:

- `ClimateEntity`
  - Typed wrapper around `HAEntityState`.
  - Parses current temperature, target temperature, target range, hvac modes, preset modes, fan modes, swing modes, min/max/step, and supported features.
- `ClimateFeatureResolver`
  - Decides which controls to show based on attributes and supported features.
- `ClimateServiceController`
  - Builds service payloads for:
    - `climate.set_hvac_mode`
    - `climate.set_temperature`
    - `climate.set_preset_mode`
    - `climate.set_fan_mode`
    - `climate.set_swing_mode`
    - `climate.set_humidity`
    - `climate.turn_on`
    - `climate.turn_off`

## Confirmed Corrections to Claude's Original Direction

- Remove personal preset target-temperature predictions from the core HA-derived detail state. If retained as local shortcuts, keep them in an explicit typed `AppConfig` entity UI policy and clearly separate them from HA state.
- Do not assume every climate entity supports `off` and `cool`; use `hvac_modes`.
- Do not couple a climate detail view to a specific fan entity ID.

## Implementation Tasks

1. Create typed climate attribute parsing.
   - `current_temperature`
   - `temperature`
   - `target_temp_low`
   - `target_temp_high`
   - `min_temp`
   - `max_temp`
   - `target_temp_step`
   - `hvac_modes`
   - `preset_modes`
   - `preset_mode`
   - `fan_modes`
   - `fan_mode`
   - `swing_modes`
   - `swing_mode`
   - `current_humidity`
   - `humidity`
   - `min_humidity`
   - `max_humidity`
   - `supported_features`

2. Decode supported feature flags.
   - Mirror HA's climate feature bit constants.
   - Use flags to decide whether to show target temperature, target range, fan mode, preset mode, swing mode, humidity, and aux heat controls.
   - If an integration omits flags but provides clear mode arrays, prefer conservative display rather than crashing.

3. Remove prototype fallback modes.
   - Do not inject `["off", "cool"]` when the entity does not provide modes.
   - If modes are missing, show current state and disable mode switching.

4. Remove direct personal-preset lookup from generic HA-derived climate controls.
   - If retained as user shortcuts, move them behind an approved typed `AppConfig` entity UI policy; Module 03 remains skipped.
   - Clearly label shortcuts as local shortcuts, not HA state.

5. Implement service payload builders.
   - Do not assemble dictionaries in SwiftUI views.
   - Validate payloads before calling services.
   - Clamp target temperatures to min/max and step.
   - Avoid sending target temperature while entity is `unavailable` or missing.

6. Add target range support.
   - For heat/cool style entities, support low/high target values when features/attributes indicate range mode.
   - Keep single-target controls for ordinary cool/heat modes.

7. Add humidity, fan, preset, and swing controls.
   - Show only when supported.
   - Use mode arrays directly from attributes.
   - Preserve HA mode strings in service calls, while formatting labels for display.

8. Add disabled/error states.
   - Missing entity: show a clear unavailable detail view.
   - `unavailable`/`unknown`: display current state and disable mutating controls.
   - Service failure: show an error surface and keep controls in sync with actual HA state.

9. Remove cross-entity assumptions.
   - Do not label or control `fan.ac_unit_controller_ac_fan` from climate detail unless Lovelace explicitly models that relationship in a future feature.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ClimateEntity.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ClimateFeatureResolver.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ClimateServiceController.swift`

Out of scope:

- Full HA more-info dialog parity.
- Inferring relationships between climate and separate fan entities.
- Automation creation or schedule editing.

## Tests and Verification

Follow the shared macOS 12 method in [`../visual-testing.md`](../visual-testing.md). Keep all default tests offline and deterministic: use fixture states and a recording service controller/transport, never a live token or Home Assistant connection.

Likely tests belong in the existing `NativeHAMacTests` target:

- `Tests/NativeHAMacTests/ClimateEntityTests.swift`
- `Tests/NativeHAMacTests/ClimateServiceControllerTests.swift`
- `Tests/NativeHAMacTests/ClimateDetailInteractionTests.swift`
- `Tests/NativeHAMacTests/ClimateDetailRenderingTests.swift` (or the existing `GUIRenderingAndPerformanceTests.swift` while the shared renderer remains there)

### Unit tests

Use table-driven `HAState` fixtures with a fixed `last_changed` timestamp. Include one complete Celsius air-conditioner fixture modeled on `climate.room_ac`, a Fahrenheit variant, a heat/cool range fixture, an `unavailable` fixture, an `unknown` fixture, and a sparse fixture with optional attributes omitted.

Test:

- parsing every attribute listed in Implementation Task 1, including absent, wrong-type, and boundary values;
- decoding each `ClimateEntityFeature` bit and combinations of bits;
- capability resolution for single target, target range, humidity, preset, fan, swing, auxiliary heat, and on/off controls;
- no invented `off`/`cool` modes when `hvac_modes` is missing, and conservative behavior when attributes and feature bits disagree;
- target clamping and step rounding at the minimum, maximum, half-step boundaries, invalid/zero step input, and both Celsius and Fahrenheit scales;
- pure angle-to-progress and progress-to-temperature conversion at the dial endpoints and wrap boundary, progress clamping, dial hit regions, the configured drag-versus-click threshold (current default: four points), and button increments;
- exact service payloads for HVAC mode, single target, target range, humidity, preset, fan mode, swing mode, on, and off, including rejection while missing or unavailable;
- optimistic-state transitions: request, matching server confirmation, a differing authoritative server value, service failure/rollback, and a stale earlier response arriving after a newer request.

Treat the constants and ordering in `/Users/jin/Documents/HA/hass-frontend/src/data/climate.ts` and the service/option semantics in the referenced `hui-climate-*-card-feature.ts` files as conformance contracts, not visual details. Add semantic assertions for them. A narrowly scoped `XCTExpectFailure` is acceptable only if such a contract test lands before the corresponding implementation fix; state the known gap and remove the expectation in this module.

### Integration tests

Run these tests on the main actor because they touch `DashboardViewModel` and SwiftUI state. Drive `ClimateDetailContent` or `EntityDetailSheet` with a `DashboardViewModel` plus a fake/recording service boundary. Verify that:

- off, idle, cooling, heating (only when `heat` is reported), unavailable, and sparse-attribute states select the correct enabled controls and labels;
- plus/minus buttons, click-to-set, and a complete drag update the local target consistently, while clamping and rounding before the service boundary;
- a drag emits no intermediate service calls if the chosen design commits on release; if production deliberately coalesces continuous calls instead, use a deterministic coalescer and assert its exact bounded behavior;
- HVAC, preset, fan-mode, and swing-mode selections preserve the raw HA strings in their service payloads and update only the intended control;
- the optimistic value remains pending until matching state arrives, an authoritative different value wins, and a service error leaves the view synchronized with HA state;
- missing/unavailable entities cannot issue a mutating service call; and
- opening and dismissing detail starts and cancels only the detail history/subscription work it owns.

Do not use a screenshot to prove service payloads, rounding, disabled behavior, or reconciliation; those require state and spy assertions.

### GUI rendering and visual regression

Run GUI tests on the main actor. NativeHA targets macOS 12 with Swift 5.6/Xcode 13.4.1, so do not use SwiftUI `ImageRenderer`. Reuse the proven `NSHostingView` in a small offscreen `NSWindow`, then capture with `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`.

Render the complete detail sheet at its current logical size of `520x620` points and `ClimateDetailContent` at a narrow `360x620`-point viewport. The latter is a clipping/responsiveness contract; if this module makes the sheet shell itself width-adaptive, render the complete narrow sheet instead. Use display scale 2, dark Aqua/dark color scheme, fixed fixture timestamps, and fixed locale/timezone where the production environment permits. The current shell is hardcoded to 520 points, so whether it should itself become narrow is an implementation-time layout decision rather than an already-supported behavior.

Write inspectable PNGs for these states to `.build/render-artifacts/` on every run:

- off with valid attributes;
- cool mode with `hvac_action: idle`;
- cool mode with `hvac_action: cooling`;
- heat mode with `hvac_action: heating`, only in the fixture whose `hvac_modes` reports heat;
- unavailable with controls disabled;
- sparse/missing optional attributes with a safe fallback; and
- complete capabilities with preset, fan, and swing controls visible at normal and narrow width.

Use stable names such as `climate-detail-cooling-520x620.png` and `climate-detail-sparse-360x620.png`. First validate the PNG signature, exact pixel dimensions, nonblank content, expected dial/control regions and color families, and settlement beyond any asynchronous loading state. These checks are only renderer smoke tests.

Do not bless current output automatically. Compare each state manually with the same fixture/capabilities in `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend. Only then place an approved PNG in `Tests/NativeHAMacTests/ReferenceImages/` and enable the existing tolerant comparison. Document the approving macOS version; review actual, expected, and preferably diff images before changing a reference. Missing references may remain optional locally until the approved set is complete, after which CI can set `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1`.

### Animation and interaction

Extend the proven `ClimateDialDrawing` experiment in `GUIRenderingAndPerformanceTests.swift`. Render deterministic dial keyframes at target progress `0`, `0.5`, and `1` (corresponding to minimum, midpoint, and maximum target temperature) with fixed current progress. Write them as `climate-dial-progress-0.png`, `climate-dial-progress-0_5.png`, and `climate-dial-progress-1.png`. Assert correct marker endpoints/regions, that all three PNGs differ, and that the final frame equals a direct render of the final state. Add meaningful idle/off and cooling/heating drawing states rather than assuming one blue cooling arc covers every mode.

Exercise the control state machine explicitly: untouched, pressed/click target, drag beyond threshold, optimistic pending, confirmed, and rejected/reconciled. Avoid scheduler-driven animation assertions and long sleeps. If the implementation exposes interpolation, render its explicit start/mid/end values and test interpolation/clamping as pure logic. Use bounded expectations or polling only for SwiftUI settlement. If substantial animation is introduced and the production code supports reduced motion, verify its reduced-motion final state. Nondeterministic trackpad automation and true event-to-frame hitch testing are deferred to a future XCUITest target under newer Xcode.

### Performance and lifecycle

Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`; Xcode 13.4.1 does not provide `XCTHitchMetric`. Prefer stored XCTest baselines over machine-dependent millisecond assertions, and consume every measured mapping/render result.

Keep preparation outside measured blocks and distinguish these paths in separate tests:

- cold parsing/feature preparation for a named 10,000-state climate fixture;
- cold initial `520x620` detail construction/rendering;
- a warmed 10,000-sample dial gesture/value-mapping pass;
- warm continuous drag through 1,000 fixed locations, measuring local interaction/update work while separately asserting the intended one-at-release or bounded-coalesced service-call policy;
- 1,000 repeated authoritative/optimistic state reconciliations; and
- 100 detail open/close cycles, followed by cancellation and weak-reference/memory checks for history subscriptions, render tasks, callbacks, and the view model/controller.

Warm caches before warm interaction measurements. Do not mix offscreen bitmap generation into the controller/gesture measurements; measure bitmap rendering separately so a regression can be attributed. Signpost metrics are optional only if the render or service scheduling path has meaningful production instrumentation. A deliberately loose, documented safety ceiling may supplement—but not replace—stored performance baselines.

### Manual QA and current limits

- Open the live `climate.room_ac` detail and compare it side-by-side with hass-frontend.
- Confirm displayed modes, target min/max/step, current/target temperature, action, and optional controls match the entity attributes and feature bits.
- Exercise plus/minus, click, drag, preset, fan, swing, and mode transitions; inspect the actual service calls and confirm each user commit produces only the intended call(s).
- Confirm external state changes and service errors reconcile the optimistic display, then repeatedly open/close detail and verify no continued history work or animation is visible.
- At both normal and narrow sizes, inspect clipping, menu labels, focus/keyboard operation, hit regions, and temperature/unit formatting.

Offscreen PNGs cannot establish data correctness, accessibility, service semantics, lifecycle safety, animation smoothness, or performance. On this macOS 12/Xcode 13.4.1 machine, do not claim coverage of app launch, real trackpad event-to-frame behavior, or hitch metrics; those remain later XCUITest/manual work.

## Dependencies

- Approved `AppConfig`/user-deviation policy for personal climate hints; skipped Module 03 is not a prerequisite.
- Module 05 for service controller extraction and error handling.
- Module 06 for shared display formatting.

## Risks

- Climate integrations vary widely. Attribute parsing must be tolerant.
- Supported feature bit constants must be kept aligned with HA.
- Local preset shortcuts can be useful, but mixing them into HA-derived controls creates false confidence. Keep them separate if retained.
- The current detail shell is fixed at `520x620`; a `360x620` content fixture can expose clipping, but changing the shell's width behavior must be confirmed against the intended dashboard presentation during implementation.
- Dial boundary angles, step rounding, the typed `AppConfig` interaction threshold, and optimistic updates are easy to make internally inconsistent. Shared pure conversion helpers and state-machine tests must drive both the controller and view.
- Snapshot stability depends on fixed appearance, scale, timestamps, locale/timezone, and a documented macOS baseline. Pixel references still cannot validate payloads or control capability logic.
- Continuous drag can accidentally create a service-call storm, while stale server updates can overwrite a newer optimistic request. Recording-controller integration tests must cover both races.
- Detail history/render tasks can outlive a dismissed sheet unless cancellation and callback ownership are explicit; screenshots will not detect that leak.

## Acceptance Criteria

- Climate controls are derived from `climate` entity attributes and supported features.
- No specific personal fan entity ID is referenced by climate detail.
- No default HVAC modes are invented when attributes do not provide them.
- Climate service payloads are centralized and tested.
- `climate.room_ac` remains usable on the live dashboard with controls matching HA's reported capabilities.
- Complete, sparse, unavailable, range, Celsius, and Fahrenheit fixtures pass parsing, feature-resolution, payload, clamping/rounding, gesture conversion, and optimistic-reconciliation tests without network access.
- Button, click, drag, HVAC, preset, fan, and swing integration tests prove the intended service-call count and authoritative-state reconciliation.
- The normal `520x620` detail and narrow `360x620` content fixtures produce valid, nonblank PNG artifacts for off, idle, cooling, supported heating, unavailable, sparse, and full-capability states; any checked-in references have been manually approved against hass-frontend on a documented macOS version and pass tolerant comparison.
- Dial start/mid/end keyframes are deterministic and distinct, with pure tests covering angle/progress conversion, clamping, step rounding, hit regions, and drag threshold behavior.
- Stored performance measurements cover cold preparation/rendering, warm drag/update work, repeated reconciliation, and 100 open/close cycles; no retained detail subscription, render task, callback, or controller remains after cancellation.
- The full module test set passes on macOS 12 with Swift 5.6/Xcode 13.4.1 without `ImageRenderer`, `XCTHitchMetric`, real credentials, or live HA state.
- Manual comparison confirms live service semantics, focus/hit behavior, narrow-layout clipping, and animation behavior; deferred XCUITest/hitch coverage is recorded rather than represented as automated coverage.
