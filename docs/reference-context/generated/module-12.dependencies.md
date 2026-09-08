# Dependency graph: module 12

- Fingerprint: `ef465e6b1a114bd7c210c61b59237ce70718343255e993e33dc7f8b6612d9791`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 121; edges: 901; cycles: 2
- Unresolved: 0; truncated: no

## Explicit seeds

- `npm:home-assistant-js-websocket@9.6.0:dist/commands.js` — `getUser`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js` — `user`
- `repo:src/common/navigate.ts` — `goBack`, `navigate`, `ensureDialogsClosed`, `NavigateOptions`, `DIALOG_WAIT_TIMEOUT`
- `repo:src/data/lovelace.ts` — `subscribeLovelaceUpdates`, `LovelaceUpdatedEvent`
- `repo:src/data/lovelace/config/types.ts` — `LovelaceConfig`, `fetchConfig`, `LovelaceDashboardBaseConfig`, `LovelaceRawConfig`, `LovelaceDashboardStrategyConfig`
- `repo:src/data/lovelace/config/view.ts` — `LovelaceBaseViewConfig`, `LovelaceViewConfig`, `computeViewIcon`, `computeViewTitle`, `LovelaceViewBackgroundConfig`, `ShowViewConfig`, `LovelaceViewHeaderConfig`, `LovelaceViewFooterConfig`, `LovelaceViewSidebarConfig`
- `repo:src/data/ws-user.ts` — `subscribeUser`, `userCollection`
- `repo:src/panels/lovelace/cards/hui-history-graph-card.ts` — `HuiHistoryGraphCard`, `DEFAULT_HOURS_TO_SHOW`
- `repo:src/panels/lovelace/create-element/create-view-element.ts` — `createViewElement`, `ALWAYS_LOADED_LAYOUTS`, `LAZY_LOAD_LAYOUTS`
- `repo:src/panels/lovelace/ha-panel-lovelace.ts` — `LovelacePanel`, `LovelacePanelConfig`, `resourcesLoaded`, `editorLoaded`
- `repo:src/panels/lovelace/hui-root.ts` — `HUIRoot`, `ExtraActionItem`, `UndoStackItem`, `ActionItem`, `SubActionItem`
- `repo:src/panels/lovelace/views/get-view-type.ts` — `getViewType`
- `repo:src/panels/lovelace/views/hui-masonry-view.ts` — `MasonryView`, `getColumnIndex`
- `repo:src/panels/lovelace/views/hui-panel-view.ts` — `PanelView`, `editCodeLoaded`
- `repo:src/panels/lovelace/views/hui-view-container.ts` — `HuiViewContainer`, `BackgroundConfig`
- `repo:src/panels/lovelace/views/hui-view-header.ts` — `HuiViewHeader`, `DEFAULT_VIEW_HEADER_LAYOUT`, `DEFAULT_VIEW_HEADER_BADGES_POSITION`, `DEFAULT_VIEW_HEADER_BADGES_WRAP`
- `repo:src/panels/lovelace/views/hui-view.ts` — `HUIView`
- `repo:src/state/auth-mixin.ts`
- `repo:src/types.ts` — `CurrentUser`, `Credential`, `MFAModule`

## Traversed packages

- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)

## Boundaries

- max-depth: 420
- package-not-allowlisted: 29
- type-only-not-followed: 306

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
