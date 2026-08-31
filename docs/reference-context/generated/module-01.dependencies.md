# Dependency graph: module 01

- Fingerprint: `75ba7d234b0d5af43ac039dbd4776508dcf55e0315594ff81e0f35fa94c8116d`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 21; edges: 143; cycles: 1
- Unresolved: 0; truncated: no

## Explicit seeds

- `npm:home-assistant-js-websocket@9.6.0:dist/connection.js` — `Connection`, `DEBUG`
- `repo:src/data/history.ts` — `EntityHistoryState`, `HistoryStream`, `HistoryStreamMessage`, `entityIdHistoryNeedsAttributes`, `subscribeHistoryStatesTimeWindow`, `subscribeHistoryStream`, `HistoryStates`, `NEED_ATTRIBUTE_DOMAINS`
- `repo:src/dialogs/more-info/ha-more-info-history.ts` — `MoreInfoHistory`, `statTypes`
- `repo:src/panels/lovelace/cards/hui-history-graph-card.ts` — `DEFAULT_HOURS_TO_SHOW`, `HuiHistoryGraphCard`

## Traversed packages

- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 69
- package-not-allowlisted: 6
- type-only-not-followed: 43

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
