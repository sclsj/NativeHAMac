# Module 07 - WeatherCard Current Conditions and Weather Detail

## Purpose

Make `weather-forecast` cards and their opened weather detail align with Home Assistant semantics for current weather display, icon mapping, units, card options, and correctly scoped forecast subscriptions.

The recorded live dashboard has three weather cards using `show_forecast: false`. Current cards and weather detail are implemented; detail forecasts use the verified WebSocket subscription API.

The [Module 07 evidence packet](../reference-context/modules/module-07-weather-card.md) is the authority for current contracts and validation. The original findings, architecture sketches, tasks, and acceptance checklist below are historical planning, not a remaining-work checklist.

Current staged status: revision 1 current-card conditions are complete and independently verified. Revision 2, defined precisely by the Module 07 evidence packet, is also complete and independently verified for the specialized weather more-info body and its one modal-scoped forecast subscription. Dashboard-card forecast rows/owners under C07-09/10 remain deferred. Next work follows the rescue index and current user priorities; Module 08 still needs a researched packet and independent research review.

## Historical Findings Before Rescue

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
   - Use `attributes.temperature_unit`, then server unit system per C07-04; do not introduce a configured fallback unit.
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
   - Preserve C07-05: without usable forecast data, render the current block for every flag combination, including both false (`!forecast || show_current !== false`).
   - Dashboard forecast demand/rendering remains deferred under C07-09/10; decoded flags alone must not start a card owner.

5. Add missing/unavailable states.
   - Missing entity: show a clear missing entity state.
   - `unavailable` or `unknown`: show the state and preserve the normal supported details action/focus matrix (C07-06/07); only a missing entity disables it.
   - Do not crash on malformed attributes.

6. Historical dashboard forecast proposal (deferred C07-09/10).
   - Use WebSocket command `weather/subscribe_forecast`.
   - Include `entity_id` and requested `type`.
   - Retain unsubscribe handle.
   - Cancel subscription when card/view disappears.
   - Recreate subscription after reconnect.

7. Historical dashboard forecast presentation proposal (deferred C07-09/10).
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

- Browser dialog chrome beyond the bounded native weather more-info body in contract revision 2.
- Weather map/radar.
- Service calls that mutate weather integrations.

## Tests and Verification

Use the shared capture and baseline method in [`../visual-testing.md`](../visual-testing.md), while keeping weather parsing, units, subscription routing, and fallback behavior under semantic tests.

### Unit tests

In `NativeHAMacTests`, add `WeatherEntityPresenterTests.swift`, `WeatherIconResolverTests.swift`, and, once forecast task 6 is implemented, `WeatherForecastStoreTests.swift`. Use table-driven fixtures for `sunny`, `cloudy`, `rainy`, `clear-night`, `unavailable`, and `unknown`; a missing entity; missing temperature/humidity/name attributes; numeric attributes encoded in each form accepted by `HAState`; and Celsius/Fahrenheit unit variants used by the live server. Verify the icon, cleaned condition, current temperature, humidity, name override/fallback, optional measurements, and explicit fallback display independently of screenshots.

Test `show_current`/`show_forecast` combinations and malformed attributes. If forecast support is implemented, use fixed daily, hourly, and twice-daily payloads to test decoding, ordering, missing optional fields, supported-feature selection, and the exact `weather/subscribe_forecast` command fields shown in `/Users/jin/Documents/HA/hass-frontend/src/data/weather.ts`. Do not claim forecast behavior is covered while tasks 6-7 remain unimplemented.

### Integration tests

Add `WeatherCardIntegrationTests.swift` using a fixture-only `DashboardViewModel`. Verify that a state change updates the intended card, malformed/missing attributes remain recoverable, and an update for one weather entity cannot mutate another card. Once `WeatherForecastStore` exists, drive it with Module 02's fake transport: test initial event, repeated forecast update, reconnect without duplicate subscription, cancellation on disappearance, and no update after unsubscribe. Keep default tests offline and free of credentials.

### GUI rendering and visual regression

Add `WeatherCardRenderingTests.swift` (or initially extend `GUIRenderingAndPerformanceTests.swift`) and run it on the main actor. Render with `MacViewPNGRenderer`: an `NSHostingView` in a small offscreen AppKit window, captured through `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`. This is required for macOS 12/Swift 5.6/Xcode 13.4.1; SwiftUI `ImageRenderer` is unavailable.

At display scale 2, render current-condition fixtures at the production 496-point card width at `496x150` and the narrow layout at `320x190`, with dark-Aqua appearance, dark color scheme, locale, timezone, and timestamps. Always produce PNGs in `.build/render-artifacts/` for sunny, cloudy, rainy, clear-night, unavailable, missing entity, missing attributes, and Celsius and Fahrenheit variants. Assert PNG signature, exact dimensions, nonblank content, condition-specific icon/color regions, and that name, temperature, humidity, and fallback regions are present before any baseline comparison.

Name artifacts by condition/unit and width, such as `weather-sunny-c-496.png`, `weather-clear-night-f-320.png`, and `weather-missing-attributes-496.png`. If forecast UI is implemented, use `496x360` for the normal daily/hourly fixtures and `320x520` for the narrow fixtures, adjusting only if the implemented forecast count is explicitly fixed and the chosen size is documented in the test name.

The live cards use `show_forecast: false`; dashboard forecast UI remains deferred. Current-card artifacts and the implemented modal forecast artifacts have separate scope in the evidence packet. Add dashboard forecast-on artifacts only when C07-09/10 enter scope. Compare every candidate manually with the same fixture/state in `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend. Never approve current output mechanically. Put only reviewed PNGs in `Tests/NativeHAMacTests/ReferenceImages/`, document the baseline macOS version, and use tolerant pixel comparison. `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1` may be enabled later when references are complete; an intentional change requires actual, expected, and preferably diff review before baseline replacement.

### Animation and interaction

No weather animation is part of the current implementation or required first milestone. Test meaningful static condition transitions instead. If the implementation adds animated condition icons or card transitions, expose the condition/progress state and render deterministic start, midpoint, and end keyframes (`0`, `0.5`, `1`), assert distinct intermediate frames and the correct final condition, and add pure transition/clamping tests. Cover reduced motion if the production code supports it. Use bounded settlement expectations rather than real-time sleeps. Card action tests must verify the correct entity detail target semantically; a pressed screenshot is not proof of routing.

### Performance and lifecycle

Add `WeatherCardPerformanceTests.swift`. Construct fixtures before measurement, consume the presentation or rendered result, and use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric` for:

- cold presenter preparation for 500 weather states with mixed/missing attributes;
- warm repeated current-state updates after caches are primed;
- if forecast support exists, repeated 1,000-item forecast payload preparation and incremental replacement without live subscriptions; and
- repeated subscribe/reconnect/unsubscribe and card/view disappearance cycles.

Measure presenter/forecast preparation separately from bitmap capture. Prefer stored XCTest baselines over machine-dependent millisecond assertions and use a broad ceiling only if documented as a safety guard. Verify memory stabilizes, forecast callbacks and receive handles are released, and hidden cards stop processing updates. Signpost metrics require real instrumentation. `XCTHitchMetric` is unavailable in Xcode 13.4.1; defer true event-to-frame and scroll hitch testing to an XCUITest target under newer Xcode.

### Manual QA

- Open all three live weather cards and compare condition name, icon, temperature unit, humidity, fallback display, padding, and narrow-width clipping with hass-frontend.
- Change or replay fixture states for sunny, cloudy, rainy, clear-night, and unavailable; ensure unavailable/missing data never appears as a default sunny state.
- If forecast support is delivered, use a non-mutating fixture configuration to compare forecast-on/off layouts and confirm reconnect produces one active subscription and hidden views unsubscribe.

## Dependencies

- Module 02 for forecast WebSocket subscriptions.
- Module 04 for full weather card config decoding.
- Module 05 for subscription lifecycle.
- Module 06 for shared state display and icon resolver conventions.

## Risks

- Weather attributes vary by integration. Presenter code must tolerate absent attributes.
- SF Symbols are an approximation of HA's MDI weather icons.
- Forecast subscriptions can be expensive if every hidden view remains subscribed. Tie subscriptions to active Lovelace view after Module 12.
- Unit and attribute conventions vary across integrations; screenshots can look plausible while the selected attribute or fallback unit is wrong, so keep the presenter contracts independent of visual comparison.
- Forecast-on snapshots would falsely imply delivered scope before tasks 6-7 are implemented. Gate those artifacts and lifecycle tests on forecast support.
- System fonts/SF Symbols and antialiasing vary by macOS version. Keep visual references OS-specific and tolerant, and use semantic icon/state assertions.
- Real-time icon animation and event-to-frame hitch behavior cannot be validated reliably with the current Xcode 13.4.1 SwiftPM tests; use deterministic states now and later XCUITest only if animation is introduced.

## Acceptance Criteria

- Live weather cards show correct current condition, temperature, and units.
- Weather icons are state-aware.
- Current-card flag behavior follows C07-05, including current display without usable forecast; dashboard forecast remains deferred. Modal forecast ignores card flags and follows C07-12 through C07-18.
- Missing, unknown, and unavailable states render intentionally.
- Forecast subscription support is designed around HA's WebSocket API and can coexist with other WebSocket subscriptions.
- Presenter and integration tests cover all required conditions, unit variants, missing/malformed data, per-card update isolation, and action targeting without network access or credentials.
- Reviewed 496-point and 320-point current-condition PNG artifacts pass signature, dimension, nonblank, and expected-region checks; approved references are tolerant and tied to a documented macOS version.
- Forecast-off visual behavior is covered. Forecast-on visual, subscription, reconnect, cancellation, and payload tests pass only when forecast tasks 6-7 are implemented; their absence is not hidden by a speculative screenshot.
- Cold/warm presenter measurements and, when applicable, the 1,000-item forecast and repeated subscription lifecycle measurements pass stored XCTest baselines without retained callbacks, tasks, or hidden-card processing.
- Manual comparison with hass-frontend confirms condition/icon/layout parity; screenshots are not used as evidence of units, subscription correctness, lifecycle, or performance.
