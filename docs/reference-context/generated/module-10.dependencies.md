# Dependency graph: module 10

- Fingerprint: `d3414b2d612e14d7e877b92f420c32bf87f2f1bee00cdfbdb7a4e4e798b62393`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 164; edges: 585; cycles: 2
- Unresolved: 1; truncated: no

## Explicit seeds

- `npm:@egjs/hammerjs@2.0.17:src/recognizerjs/recognizer-constructor.js` — `Recognizer`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/attribute.js` — `AttrRecognizer`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/pan.js` — `PanRecognizer`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/tap.js` — `TapRecognizer`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/components/dropdown-item/dropdown-item.js` — `WaDropdownItem`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/components/dropdown/dropdown.js` — `WaDropdown`, `openDropdowns`
- `npm:home-assistant-js-websocket@9.6.0:dist/commands.js` — `callService`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `callService`
- `repo:src/common/entity/compute_attribute_display.ts` — `computeAttributeValueDisplay`, `computeAttributeValueToParts`
- `repo:src/common/entity/compute_state_display.ts` — `computeStateDisplay`, `computeStateDisplayFromEntityAttributes`, `computeStateToPartsFromEntityAttributes`, `NUMERICAL_DOMAINS`, `MONETARY_TYPE_MAP`, `DATE_TIME_DOMAINS`
- `repo:src/common/entity/state_active.ts` — `stateActive`
- `repo:src/common/entity/state_color.ts` — `stateColorCss`, `stateColorProperties`, `STATE_COLORED_DOMAIN`, `domainStateColorProperties`, `domainColorProperties`
- `repo:src/common/entity/supports-feature.ts` — `supportsFeature`, `supportsFeatureFromAttributes`
- `repo:src/common/number/clamp.ts` — `clamp`
- `repo:src/common/number/format_number.ts` — `formatNumber`, `formatNumberToParts`, `numberFormatToLocale`, `getNumberFormatter`, `getDefaultFormatOptions`, `numberFormatCache`
- `repo:src/common/translations/blank_before_percent.ts` — `blankBeforePercent`
- `repo:src/common/translations/blank_before_unit.ts` — `blankBeforeUnit`
- `repo:src/common/util/debounce.ts` — `debounce`
- `repo:src/components/ha-control-circular-slider.ts` — `HaControlCircularSlider`, `ControlCircularSliderMode`, `ActiveSlider`, `xy2polar`, `MAX_ANGLE`, `rad2deg`, `ROTATE_ANGLE`, `A11Y_KEY_CODES`, `RADIUS`
- `repo:src/components/ha-control-select-menu.ts` — `HaControlSelectMenu`, `SelectOption`
- `repo:src/components/ha-dropdown-item.ts` — `HaDropdownItem`
- `repo:src/components/ha-dropdown.ts` — `HaDropdown`
- `repo:src/data/climate.ts` — `CLIMATE_HVAC_ACTION_TO_MODE`, `ClimateEntityFeature`, `HVAC_MODES`, `compareClimateHvacModes`, `HvacAction`, `HvacMode`, `hvacModeOrdering`
- `repo:src/data/entity/entity_attributes.ts` — `DOMAIN_ATTRIBUTES_UNITS`, `TEMPERATURE_ATTRIBUTES`
- `repo:src/dialogs/more-info/components/ha-more-info-control-select-container.ts` — `HaMoreInfoControlSelectContainer`
- `repo:src/dialogs/more-info/components/more-info-control-style.ts` — `moreInfoControlStyle`
- `repo:src/dialogs/more-info/controls/more-info-climate.ts` — `MoreInfoClimate`, `MainControl`
- `repo:src/resources/svg-arc.ts` — `svgArc`, `ArcOptions`, `toRadian`, `createRotateMatrix`, `addVector`, `rotateVector`, `Matrix`, `Vector`
- `repo:src/resources/theme/color/color.globals.ts` — `colorStyles`, `darkColorStyles`
- `repo:src/state-control/climate/ha-state-control-climate-humidity.ts` — `HaStateControlClimateHumidity`
- `repo:src/state-control/climate/ha-state-control-climate-temperature.ts` — `HaStateControlClimateTemperature`, `SLIDER_MODES`, `Target`
- `repo:src/state-control/state-control-circular-slider-style.ts` — `createStateControlCircularSliderController`, `stateControlCircularSliderStyle`
- `repo:src/state/connection-mixin.ts` — `connectionMixin`

## Traversed packages

- `@egjs/hammerjs@2.0.17` (package.json SHA-256 `d34bedf030719df4954350236eeffb2e5489eff5e99861b250c181e395e84250`)
- `@home-assistant/webawesome@3.7.0-ha.0` (package.json SHA-256 `1e1e913cc1e520c42bc53cfb96376c745a2b39379e6dea05414fa9bc9b3cbea7`)
- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 91
- package-not-allowlisted: 92
- type-only-not-followed: 145
- unresolved: 1

## Unresolved or nonliteral edges

- `repo:src/resources/translations-metadata.ts`: unresolved-import

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
