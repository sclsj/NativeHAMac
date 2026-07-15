# Module 10 - ClimateDetailContent Capabilities and Service Semantics

## Purpose

Make climate detail controls driven by the entity's actual HA attributes and supported features, instead of prototype defaults and personal configuration.

The live server includes `climate.room_ac`, so this module should focus first on air-conditioner style climate entities before broad thermostat coverage.

## Current-Code Findings

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

- Remove personal preset target-temperature predictions from the core detail surface. If a user wants local shortcuts, they belong in Module 03 profile preferences and should be clearly separate from HA state.
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

4. Remove AppConfig preset target temperatures from default climate UI.
   - If retained as user shortcuts, move them behind profile preference APIs from Module 03.
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

Add unit tests for:

- Climate attribute parsing with complete and sparse fixtures.
- Supported feature flag decoding.
- HVAC mode list display.
- No fallback mode injection when `hvac_modes` is missing.
- Target temperature clamping and step rounding.
- Service payloads for mode, target temperature, preset, fan mode, and swing mode.
- Disabled controls for unavailable/missing entity.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/ClimateEntityTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/ClimateServiceControllerTests.swift`

Manual QA:

- Open `climate.room_ac`.
- Confirm displayed modes match HA attributes.
- Confirm target temperature min/max/step match HA.
- Confirm unsupported controls are not shown.
- Confirm changing a control sends exactly one intended service call.
- Confirm service errors do not desynchronize displayed state from HA state.

## Dependencies

- Module 03 for removing personal climate preset config from core UI.
- Module 05 for service controller extraction and error handling.
- Module 06 for shared display formatting.

## Risks

- Climate integrations vary widely. Attribute parsing must be tolerant.
- Supported feature bit constants must be kept aligned with HA.
- Local preset shortcuts can be useful, but mixing them into HA-derived controls creates false confidence. Keep them separate if retained.

## Acceptance Criteria

- Climate controls are derived from `climate` entity attributes and supported features.
- No specific personal fan entity ID is referenced by climate detail.
- No default HVAC modes are invented when attributes do not provide them.
- Climate service payloads are centralized and tested.
- `climate.room_ac` remains usable on the live dashboard with controls matching HA's reported capabilities.

