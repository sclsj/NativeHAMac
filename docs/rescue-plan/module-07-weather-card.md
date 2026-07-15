# Module 07 - WeatherCard Current Conditions and Forecast Support

## Purpose

Make `weather-forecast` cards align with Home Assistant semantics for current weather display, icon mapping, units, card options, and future forecast subscriptions.

The live dashboard currently has three weather cards and all use `show_forecast: false`, so current-conditions correctness is the first milestone. Forecast subscription support can follow once WebSocket subscriptions are reliable.

## Current-Code Findings

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`:

- `WeatherCard` renders a static SF Symbol and a small subset of weather attributes.
- The implementation does not subscribe to forecasts.
- `show_forecast` is decoded in the model but the view does not implement forecast rows or charts.
- Weather icons are not mapped from HA weather states.
- Unit handling is partial and does not consistently use HA unit-system or entity attributes.
- Missing/unavailable weather entities do not have HA-like explicit fallback behavior.

Confirmed in `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`:

- `LovelaceCard` includes only sparse weather fields.
- Many HA weather-card fields are not preserved yet.

## Reference Implementation Paths

- `/Users/jin/Documents/HA/hass-frontend/src/data/weather.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/hui-weather-forecast-card.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/dialogs/more-info/controls/more-info-weather.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/state_icon.ts`
- `/Users/jin/Documents/HA/hass-frontend/src/common/entity/compute_state_display.ts`

## Target Architecture

Use a small weather-specific model layer:

- `WeatherCardConfig`
  - Decoded from Lovelace card config.
  - Preserves `entity`, `name`, `show_current`, `show_forecast`, `forecast_type`, `secondary_info_attribute`, and card actions.
- `WeatherEntityPresenter`
  - Builds current condition display data from `HAEntityState`.
  - Resolves icon, temperature, humidity, pressure, wind speed, wind bearing, precipitation, visibility, and attribution if present.
- `WeatherForecastStore`
  - Later subscribes to `weather/subscribe_forecast` through Module 02.
  - Owns forecast rows per entity and forecast type.

## Confirmed Corrections to Claude's Original Direction

- Weather forecast support is not the top priority for the live dashboard because current live cards use `show_forecast: false`.
- Current weather display is still important: state icon, temperature, units, and unavailable handling should be fixed before forecast UI is added.
- Do not poll REST for forecasts if HA frontend uses WebSocket forecast subscription and Module 02 is available.

## Implementation Tasks

1. Expand weather Lovelace decoding.
   - Add or preserve fields:
     - `entity`
     - `name`
     - `show_current`
     - `show_forecast`
     - `forecast_type`
     - `secondary_info_attribute`
     - `tap_action`
     - `hold_action`
     - `double_tap_action`
   - Preserve unknown keys for future compatibility.

2. Implement current condition presenter.
   - Resolve display name with row/card override.
   - Display weather state using HA-like state display cleanup.
   - Display current temperature from `attributes.temperature`.
   - Use `attributes.temperature_unit` if present, otherwise server unit system, otherwise configured fallback.
   - Display humidity, pressure, wind speed, precipitation, and visibility only when present.

3. Implement icon mapping.
   - Map common HA weather states:
     - `clear-night`
     - `cloudy`
     - `fog`
     - `hail`
     - `lightning`
     - `lightning-rainy`
     - `partlycloudy`
     - `pouring`
     - `rainy`
     - `snowy`
     - `snowy-rainy`
     - `sunny`
     - `windy`
     - `windy-variant`
     - `exceptional`
   - Use SF Symbols initially, but isolate mapping so Material Design Icons can replace it later.

4. Honor `show_current`.
   - If `show_current == false`, suppress the current condition block.
   - If both current and forecast are hidden, render a compact card title or empty state consistent with HA behavior.

5. Add missing/unavailable states.
   - Missing entity: show a clear missing entity state.
   - `unavailable` or `unknown`: show the state and disable action affordances.
   - Do not crash on malformed attributes.

6. Add forecast subscription after Module 02.
   - Use WebSocket command `weather/subscribe_forecast`.
   - Include `entity_id` and requested `type`.
   - Retain unsubscribe handle.
   - Cancel subscription when card/view disappears.
   - Recreate subscription after reconnect.

7. Implement forecast presentation.
   - Daily and hourly forecast rows should display datetime, icon, temperature, templow when present, precipitation probability/amount when present, and condition.
   - Respect `show_forecast`.
   - Keep forecast layout simple but dense for macOS.

8. Add card action plumbing.
   - Decode actions now.
   - Implement only actions already supported by the app, such as opening details.
   - Leave advanced Lovelace action behavior to a later shared action module if needed.

## File Ownership and Scope

Primary files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`

Likely new files:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/WeatherEntityPresenter.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/WeatherIconResolver.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/WeatherForecastStore.swift`

Out of scope:

- Full weather detail dialog parity.
- Weather map/radar.
- Service calls that mutate weather integrations.

## Tests and Verification

Add unit tests for:

- Current temperature and unit formatting.
- Weather state to icon mapping.
- Missing and unavailable entity display.
- `show_current` and `show_forecast` config behavior.
- Forecast subscription command construction after Module 02.
- Forecast payload decoding for daily and hourly examples.

Suggested test files:

- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/WeatherEntityPresenterTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/WeatherIconResolverTests.swift`
- `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHAMacTests/WeatherForecastStoreTests.swift`

Manual QA:

- Open all three live weather cards.
- Confirm the cards render useful current conditions even with `show_forecast: false`.
- Confirm the state icon changes when testing with fixture states such as `sunny`, `cloudy`, `rainy`, and `clear-night`.
- Confirm unavailable weather entities do not appear as sunny/default weather.
- With a fixture or temporary non-mutating test config, confirm forecast rows render when `show_forecast: true`.

## Dependencies

- Module 02 for forecast WebSocket subscriptions.
- Module 04 for full weather card config decoding.
- Module 05 for subscription lifecycle.
- Module 06 for shared state display and icon resolver conventions.

## Risks

- Weather attributes vary by integration. Presenter code must tolerate absent attributes.
- SF Symbols are an approximation of HA's MDI weather icons.
- Forecast subscriptions can be expensive if every hidden view remains subscribed. Tie subscriptions to active Lovelace view after Module 12.

## Acceptance Criteria

- Live weather cards show correct current condition, temperature, and units.
- Weather icons are state-aware.
- `show_current` and `show_forecast` are honored.
- Missing, unknown, and unavailable states render intentionally.
- Forecast subscription support is designed around HA's WebSocket API and can coexist with other WebSocket subscriptions.

