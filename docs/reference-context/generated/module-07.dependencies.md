# Dependency graph: module 07

- Fingerprint: `cf5e507742d0a9e61fa63a175d72ef88d7574931210f30cd39f243cfe524beb7`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 128; edges: 817; cycles: 5
- Unresolved: 0; truncated: no

## Explicit seeds

- `npm:home-assistant-js-websocket@9.6.0:dist/connection.js` — `Connection`, `DEBUG`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `unsubscribeEvents`
- `npm:home-assistant-js-websocket@9.6.0:dist/types.d.ts` — `HassConfig`
- `repo:src/common/datetime/format_date.ts` — `formatDate`, `formatDateMem`
- `repo:src/common/datetime/format_time.ts` — `formatTime`, `formatTimeMem`
- `repo:src/common/entity/compute_attribute_display.ts` — `computeAttributeValueDisplay`, `computeAttributeValueToParts`
- `repo:src/common/entity/compute_entity_name_display.ts` — `computeEntityNameDisplay`, `EntityNameItem`, `EntityNameOptions`, `DEFAULT_SEPARATOR`, `computeEntityNameList`
- `repo:src/common/entity/compute_state_display.ts` — `computeStateDisplay`, `computeStateDisplayFromEntityAttributes`, `computeStateToPartsFromEntityAttributes`, `NUMERICAL_DOMAINS`, `MONETARY_TYPE_MAP`, `DATE_TIME_DOMAINS`
- `repo:src/common/entity/state_icon.ts` — `stateIcon`
- `repo:src/common/entity/supports-feature.ts` — `supportsFeature`, `supportsFeatureFromAttributes`
- `repo:src/common/number/format_number.ts` — `formatNumber`, `formatNumberToParts`, `numberFormatToLocale`, `getNumberFormatter`, `getDefaultFormatOptions`, `numberFormatCache`
- `repo:src/common/number/round.ts` — `round`
- `repo:src/common/translations/blank_before_unit.ts` — `blankBeforeUnit`
- `repo:src/components/ha-relative-time.ts` — `HaRelativeTime`
- `repo:src/data/entity/entity.ts` — `UNAVAILABLE`, `UNKNOWN`
- `repo:src/data/lovelace/config/card.ts` — `LovelaceCardConfig`
- `repo:src/data/weather.ts` — `ForecastAttribute`, `ForecastEvent`, `WeatherEntityFeature`, `getDefaultForecastType`, `getForecast`, `getSecondaryWeatherAttribute`, `getSupportedForecastTypes`, `getWeatherStateIcon`, `getWeatherUnit`, `getWind`, `subscribeForecast`, `weatherAttrIcons`, `weatherIcons`, `WeatherEntityAttributes`, `ForecastType`, `getLegacyForecast`, `WeatherEntity`, `getWeatherExtrema`, `ModernForecastType`, `weatherSVGs`, `getWeatherStateSVG`, `getWindBearing`, `isForecastHourly`, `isForecastTwiceDaily`, `cloudyStates`, `rainStates`, `windyStates`, `snowyStates`, `lightningStates`, `getWindBearingText`, `EIGHT_HOURS`, `DAY_IN_MILLISECONDS`, `cardinalDirections`
- `repo:src/dialogs/more-info/controls/more-info-weather.ts` — `MoreInfoWeather`
- `repo:src/panels/lovelace/cards/hui-weather-forecast-card.ts` — `HuiWeatherForecastCard`
- `repo:src/panels/lovelace/cards/types.ts` — `WeatherForecastCardConfig`
- `repo:src/panels/lovelace/common/directives/action-handler-directive.ts` — `actionHandler`, `actionHandlerBind`, `ActionHandlerElement`, `ActionHandlerType`, `getActionHandler`
- `repo:src/panels/lovelace/common/handle-action.ts` — `handleAction`, `ActionConfigParams`
- `repo:src/panels/lovelace/common/has-action.ts` — `hasAction`
- `repo:src/panels/lovelace/editor/config-elements/hui-weather-forecast-card-editor.ts` — `HuiWeatherForecastCardEditor`, `cardConfigStruct`
- `repo:src/types.ts` — `HomeAssistant`, `HomeAssistantFormatters`, `HomeAssistantRegistries`, `HomeAssistantInternationalization`, `HomeAssistantApi`, `HomeAssistantConnection`, `HomeAssistantUI`, `HomeAssistantConfig`, `ValuePart`, `TranslationMetadata`, `ServiceCallRequest`, `ServiceCallResponse`, `CallWS`, `ThemeSettings`, `Panels`, `HassLoggingConfig`, `CurrentUser`, `Translation`, `Context`, `PanelInfo`, `LogFileDisabledReason`, `Credential`, `MFAModule`

## Traversed packages

- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 315
- package-not-allowlisted: 69
- type-only-not-followed: 257

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
