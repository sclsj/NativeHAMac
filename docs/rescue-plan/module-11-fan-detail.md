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

Add unit tests for:

- Fan attribute parsing with sparse and complete fixtures.
- Supported feature flag decoding.
- Speed button generation for large and small `percentage_step`.
- Slider fallback for many speed levels.
- Percentage snapping and clamping.
- Service payloads for percentage, preset, direction, oscillation, on, and off.
- Disabled controls for unavailable/missing fan.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/FanEntityTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/FanServiceControllerTests.swift`

Manual QA:

- Open `fan.ac_unit_controller_ac_fan`.
- Confirm the displayed speed controls match the entity's `percentage_step`.
- Confirm presets appear only if HA reports `preset_modes`.
- Confirm direction and oscillation appear only if supported.
- Confirm service calls update HA state and the UI waits for realtime state confirmation.

## Dependencies

- Module 05 for service controller extraction and error handling.
- Module 06 for shared state display and disabled-state conventions.

## Risks

- Some integrations expose both percentage and presets in ways that are mutually exclusive. UI should show both only if HA attributes support both.
- Setting percentage to 0 versus calling `turn_off` can differ by integration. Prefer HA frontend semantics and test against live fan behavior carefully.
- Feature constants must stay aligned with HA.

## Acceptance Criteria

- Fan speeds are derived from HA `percentage_step`, not hardcoded.
- Preset, direction, and oscillation controls are capability-driven.
- Fan service payloads are centralized and tested.
- Unavailable/missing fans have intentional disabled UI.
- The live fan remains controllable without personal hardcoded assumptions.

