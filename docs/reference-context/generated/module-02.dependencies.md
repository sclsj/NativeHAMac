# Dependency graph: module 02

- Fingerprint: `0d5d18dbc77d36c1f5ee5a16023c0a658788fa96c9394ecc188217280864d4c1`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 31; edges: 61; cycles: 0
- Unresolved: 0; truncated: no

## Explicit seeds

- `npm:home-assistant-js-websocket@9.6.0:dist/connection.js` — `Connection`, `DEBUG`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `supportedFeatures`, `unsubscribeEvents`
- `npm:home-assistant-js-websocket@9.6.0:dist/socket.js` — `createSocket`, `DEBUG`, `MSG_TYPE_AUTH_INVALID`, `MSG_TYPE_AUTH_OK`, `MSG_TYPE_AUTH_REQUIRED`
- `repo:src/data/entity/entity_registry.ts` — `EntityRegistryDisplayEntryResponse`, `fetchEntityRegistryDisplay`, `EntityCategory`
- `repo:src/data/frontend.ts` — `fetchFrontendUserData`, `ValidUserDataKey`
- `repo:src/data/history.ts` — `subscribeHistoryStream`, `HistoryStates`, `HistoryStream`, `HistoryStreamMessage`, `EntityHistoryState`
- `repo:src/data/lovelace/config/types.ts` — `fetchConfig`, `LovelaceRawConfig`, `LovelaceConfig`, `LovelaceDashboardStrategyConfig`, `LovelaceDashboardBaseConfig`
- `repo:src/data/translation.ts` — `FrontendLocaleData`, `NumberFormat`, `TimeFormat`, `DateFormat`, `FirstWeekday`, `TimeZone`
- `repo:src/data/weather.ts` — `subscribeForecast`, `ModernForecastType`, `ForecastEvent`, `ForecastAttribute`
- `repo:src/entrypoints/core.ts` — `connProm`, `clearUrlParams`, `authProm`
- `repo:src/util/websocket.ts` — `callWS`, `_debugConnection`

## Traversed packages

- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- package-not-allowlisted: 2
- type-only-not-followed: 17

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
