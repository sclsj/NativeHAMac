# Dependency graph: module 11

- Fingerprint: `c04844f499238dd4b9c8ed73ec79476bb5e7a1c9d44eff33ae4743a6b6be53b1`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 200; edges: 693; cycles: 3
- Unresolved: 1; truncated: no

## Explicit seeds

- `npm:@egjs/hammerjs@2.0.17:src/manager.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizerjs/recognizer-constructor.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/attribute.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/pan.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/press.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/swipe.js`
- `npm:@egjs/hammerjs@2.0.17:src/recognizers/tap.js`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/components/dropdown-item/dropdown-item.js`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/components/dropdown/dropdown.js`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/components/dropdown/dropdown.styles.js`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/events/select.js`
- `npm:@home-assistant/webawesome@3.7.0-ha.0:dist/internal/animate.js`
- `npm:@material/web@2.4.1:iconbutton/internal/icon-button.js` — `IconButton`, `iconButtonBaseClass`
- `npm:home-assistant-js-websocket@9.6.0:dist/commands.js` — `callService`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `callService`
- `repo:src/common/entity/compute_attribute_display.ts` — `computeAttributeNameDisplay`, `computeAttributeValueDisplay`, `computeAttributeValueToParts`
- `repo:src/common/entity/compute_state_display.ts` — `computeStateDisplay`, `computeStateDisplayFromEntityAttributes`, `computeStateToPartsFromEntityAttributes`, `NUMERICAL_DOMAINS`, `MONETARY_TYPE_MAP`, `DATE_TIME_DOMAINS`
- `repo:src/common/entity/state_active.ts` — `stateActive`
- `repo:src/common/entity/state_color.ts` — `stateColorCss`, `stateColorProperties`, `STATE_COLORED_DOMAIN`, `domainStateColorProperties`, `domainColorProperties`
- `repo:src/common/entity/supports-feature.ts` — `supportsFeature`, `supportsFeatureFromAttributes`
- `repo:src/common/number/format_number.ts` — `formatNumber`, `formatNumberToParts`, `numberFormatToLocale`, `getNumberFormatter`, `getDefaultFormatOptions`, `numberFormatCache`
- `repo:src/common/translations/blank_before_percent.ts` — `blankBeforePercent`
- `repo:src/common/translations/blank_before_unit.ts` — `blankBeforeUnit`
- `repo:src/components/ha-attribute-icon.ts` — `HaAttributeIcon`
- `repo:src/components/ha-control-button.ts` — `HaControlButton`
- `repo:src/components/ha-control-select-menu.ts` — `HaControlSelectMenu`, `SelectOption`
- `repo:src/components/ha-control-select.ts` — `HaControlSelect`, `ControlSelectOption`
- `repo:src/components/ha-control-slider.ts` — `HaControlSlider`, `SliderMode`, `TooltipPosition`, `TooltipMode`, `A11Y_KEY_CODES`
- `repo:src/components/ha-control-switch.ts` — `HaControlSwitch`
- `repo:src/components/ha-dropdown-item.ts` — `HaDropdownItem`
- `repo:src/components/ha-dropdown.ts` — `HaDropdown`
- `repo:src/components/ha-outlined-icon-button.ts` — `HaOutlinedIconButton`
- `repo:src/data/entity/entity_attributes.ts` — `DOMAIN_ATTRIBUTES_UNITS`
- `repo:src/data/fan.ts` — `FAN_SPEEDS`, `FanEntityFeature`, `computeFanSpeedCount`, `computeFanSpeedIcon`, `computeFanSpeedStateDisplay`, `fanPercentageToSpeed`, `fanSpeedToPercentage`, `FanSpeed`, `FanEntity`, `FanEntityAttributes`
- `repo:src/data/icons.ts` — `attributeIcon`, `getPlatformIcons`, `getIconFromTranslations`, `getComponentIcons`, `PlatformIcons`, `resources`, `getHassIcons`, `getIconFromRange`, `ComponentIcons`, `ServiceIcons`, `TriggerIcons`, `ConditionIcons`, `IconCategory`, `IconResources`, `CategoryType`, `sortedRangeCache`
- `repo:src/dialogs/more-info/components/ha-more-info-control-select-container.ts` — `HaMoreInfoControlSelectContainer`
- `repo:src/dialogs/more-info/components/ha-more-info-state-header.ts` — `HaMoreInfoStateHeader`
- `repo:src/dialogs/more-info/components/more-info-control-style.ts` — `moreInfoControlStyle`
- `repo:src/dialogs/more-info/controls/more-info-fan.ts` — `MoreInfoFan`
- `repo:src/resources/state-control-styles.ts` — `stateControlToggleStyle`
- `repo:src/state-control/fan/ha-state-control-fan-speed.ts` — `HaStateControlFanSpeed`
- `repo:src/state-control/ha-state-control-toggle.ts` — `HaStateControlToggle`
- `repo:src/state/connection-mixin.ts` — `connectionMixin`

## Traversed packages

- `@egjs/hammerjs@2.0.17` (package.json SHA-256 `d34bedf030719df4954350236eeffb2e5489eff5e99861b250c181e395e84250`)
- `@home-assistant/webawesome@3.7.0-ha.0` (package.json SHA-256 `1e1e913cc1e520c42bc53cfb96376c745a2b39379e6dea05414fa9bc9b3cbea7`)
- `@material/web@2.4.1` (package.json SHA-256 `05c67eceeff26ef2ec8ba727fad6ee62b6807640b1cbe4e8a1f2a3e69fdea11b`)
- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 88
- package-not-allowlisted: 117
- type-only-not-followed: 156
- unresolved: 1

## Unresolved or nonliteral edges

- `repo:src/resources/translations-metadata.ts`: unresolved-import

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
