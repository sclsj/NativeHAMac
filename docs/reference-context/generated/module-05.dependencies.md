# Dependency graph: module 05

- Fingerprint: `d684771c4806d476448a65b60536dce7dec32929ea7d3cb4378a4ec78bb12156`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 130; edges: 811; cycles: 1
- Unresolved: 0; truncated: no

## Explicit seeds

- `npm:home-assistant-js-websocket@9.6.0:dist/collection.js` — `getCollection`, `DEBUG`, `UNSUB_GRACE_PERIOD`
- `npm:home-assistant-js-websocket@9.6.0:dist/commands.js` — `callService`, `getStates`
- `npm:home-assistant-js-websocket@9.6.0:dist/connection.js` — `Connection`, `DEBUG`
- `npm:home-assistant-js-websocket@9.6.0:dist/entities.js` — `entitiesColl`, `processEvent`, `subscribeEntities`, `subscribeUpdates`, `legacyFetchEntities`, `legacySubscribeUpdates`, `legacyProcessEvent`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `callService`, `states`
- `repo:src/common/entity/can_toggle_domain.ts` — `canToggleDomain`
- `repo:src/common/entity/can_toggle_state.ts` — `canToggleState`
- `repo:src/common/entity/compute_domain.ts` — `computeDomain`
- `repo:src/common/entity/compute_state_display.ts` — `computeStateDisplay`, `computeStateDisplayFromEntityAttributes`, `computeStateToPartsFromEntityAttributes`, `NUMERICAL_DOMAINS`, `MONETARY_TYPE_MAP`, `DATE_TIME_DOMAINS`
- `repo:src/common/entity/compute_state_name.ts` — `computeStateName`, `computeStateNameFromEntityAttributes`
- `repo:src/components/entity/ha-entity-toggle.ts` — `HaEntityToggle`, `isOn`
- `repo:src/data/lovelace.ts` — `getLovelaceCollection`, `subscribeLovelaceUpdates`, `LovelaceUpdatedEvent`
- `repo:src/data/lovelace/config/types.ts` — `LovelaceConfig`, `fetchConfig`, `LovelaceDashboardBaseConfig`, `LovelaceRawConfig`, `LovelaceDashboardStrategyConfig`
- `repo:src/data/service.ts` — `serviceCallWillDisconnect`
- `repo:src/layouts/hass-error-screen.ts` — `HassErrorScreen`
- `repo:src/layouts/hass-loading-screen.ts` — `HassLoadingScreen`
- `repo:src/panels/lovelace/cards/hui-history-graph-card.ts` — `HuiHistoryGraphCard`, `DEFAULT_HOURS_TO_SHOW`
- `repo:src/panels/lovelace/common/entity/toggle-entity.ts` — `toggleEntity`
- `repo:src/panels/lovelace/common/entity/turn-on-off-entity.ts` — `turnOnOffEntity`
- `repo:src/panels/lovelace/ha-panel-lovelace.ts` — `LovelacePanel`, `LovelacePanelConfig`, `resourcesLoaded`, `editorLoaded`
- `repo:src/panels/lovelace/hui-root.ts` — `HUIRoot`, `ExtraActionItem`, `UndoStackItem`, `ActionItem`, `SubActionItem`
- `repo:src/panels/lovelace/views/hui-view.ts` — `HUIView`

## Traversed packages

- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 370
- package-not-allowlisted: 24
- type-only-not-followed: 267

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
