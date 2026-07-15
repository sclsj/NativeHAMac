# Module 06 - EntitiesCard, EntityRow, State Display, and Entity Icons

## Purpose

Make `entities` cards feel like Home Assistant instead of a basic list of strings. This module covers state display, entity names, icons, missing entities, toggle behavior, row options, and secondary information.

The live dashboard has 12 `entities` cards, so this module has high user-visible impact.

## Current-Code Findings

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
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/entity-rows/hui-generic-entity-row.ts`
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
- Do not place hardcoded personal display names or personal entity hiding in `EntitiesCard`. That belongs in Module 03 profile policy.
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
   - Row `name` override wins unless explicitly false/empty semantics are modeled later.
   - Then `attributes.friendly_name`.
   - Then entity object ID transformed into title-like text.

4. Implement icon resolution.
   - Row `icon` override wins.
   - Domain-based fallback should cover live domains: `sensor`, `automation`, `switch`, `device_tracker`, `button`, `binary_sensor`, `zone`, `number`, `script`, `select`, `update`, `climate`, `fan`, and `weather`.
   - Add state-aware cases for binary sensors, device trackers, switches, automations, updates, covers if added later, and weather if shown in entity rows.

5. Implement toggle eligibility.
   - Align domain list with HA frontend `DOMAINS_TOGGLE`: `fan`, `input_boolean`, `light`, `switch`, `group`, `automation`, `humidifier`, `valve`.
   - Include `fan` percentage support through Module 11 where appropriate.
   - Disable toggles for missing, `unavailable`, and unknown entities.
   - Use explicit service support if a future capability model exposes it.

6. Fix header toggle behavior.
   - Decode and honor `show_header_toggle`.
   - Use HA-like default: show header toggle when the card has enough toggleable entities and it is not explicitly disabled.
   - Header toggle should call service only for entities currently eligible for toggle.

7. Add secondary information support.
   - Start with `last-changed`, `last-updated`, and entity attribute names used by current dashboard.
   - Format timestamps using the app timezone/locale.
   - Keep unsupported values visually absent rather than showing raw config.

8. Add missing entity row state.
   - Render the row with a warning icon and a clear missing-state label.
   - Do not crash when Lovelace references an entity not returned by `/api/states`.

9. Keep action support conservative.
   - `tap_action`, `hold_action`, and `double_tap_action` should be decoded now.
   - Implement only existing app-supported actions in this module.
   - Leave navigation/more-info expansion for a later UI module unless required by another plan.

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

Add unit tests for:

- Friendly name fallback order.
- Numeric state with unit.
- `unknown` and `unavailable` display.
- Missing entity row display data.
- Toggle eligibility by domain and state.
- Header toggle respects `show_header_toggle`.
- Device tracker icon/display for `home` and `not_home`.
- Binary sensor icon/display based on state and device class.
- Timestamp secondary info formatting.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/EntityDisplayFormatterTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/EntityIconResolverTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/EntityActionResolverTests.swift`

Manual QA:

- Open each live `entities` card.
- Confirm row labels match HA friendly names where available.
- Confirm numeric sensors show units.
- Confirm device trackers and binary sensors do not look like generic sensors when state-specific icons are available.
- Confirm unavailable or unknown entities are visible and understandable.
- Confirm header toggles do not appear on cards where HA would hide them.
- Confirm no personal entity names are hardcoded in row rendering.

## Dependencies

- Module 04 for robust row config decoding.
- Module 05 for moving display and action logic out of `DashboardViewModel`.
- Module 03 for profile-based hidden entity handling.

## Risks

- Exact HA display localization is large. Start with faithful structural behavior and current-dashboard domains, then expand.
- SF Symbols do not map one-to-one with HA's Material Design Icons. Keep the resolver isolated so the icon backend can change later.
- Header toggle can call many services. Keep it opt-in to eligible entities only and show clear disabled states.

## Acceptance Criteria

- All live `entities` cards render without unsupported row crashes.
- State display is centralized and tested.
- Toggle eligibility is centralized and aligned with HA's domain model for the supported domains.
- Missing, unavailable, and unknown entities are displayed intentionally.
- Row-level `name`, `icon`, and `secondary_info` are honored.
- `DashboardViewModel` no longer contains the primary state-display implementation.

