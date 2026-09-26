# Dependency graph: module 08

- Fingerprint: `3495d18baf3ef246eb8f757c98ee3c65491cca659f19fac7406a8b83d016a27c`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 177; edges: 2124; cycles: 1
- Unresolved: 2; truncated: no

## Explicit seeds

- `npm:comlink@4.4.2:dist/esm/comlink.mjs`
- `npm:home-assistant-js-websocket@9.6.0:dist/collection.js`
- `npm:home-assistant-js-websocket@9.6.0:dist/commands.js`
- `npm:home-assistant-js-websocket@9.6.0:dist/connection.js` — `Connection`, `DEBUG`
- `npm:home-assistant-js-websocket@9.6.0:dist/messages.js`
- `npm:home-assistant-js-websocket@9.6.0:dist/store.js`
- `npm:marked@18.0.5:lib/marked.esm.js`
- `npm:object-hash@3.0.0:dist/object_hash.js`
- `npm:object-hash@3.0.0:index.js`
- `npm:xss@1.0.15:lib/default.js`
- `npm:xss@1.0.15:lib/index.js`
- `npm:xss@1.0.15:lib/parser.js`
- `npm:xss@1.0.15:lib/util.js`
- `npm:xss@1.0.15:lib/xss.js`
- `repo:src/common/dom/is-navigation-click.ts` — `isNavigationClick`
- `repo:src/common/navigate.ts` — `navigate`, `NavigateOptions`, `ensureDialogsClosed`, `DIALOG_WAIT_TIMEOUT`
- `repo:src/components/ha-alert.ts`
- `repo:src/components/ha-card.ts`
- `repo:src/components/ha-markdown-element.ts` — `HaMarkdownElement`, `markdownCache`, `h`, `_gitHubMarkdownAlerts`
- `repo:src/components/ha-markdown.ts` — `HaMarkdown`
- `repo:src/data/ws-templates.ts` — `RenderTemplateError`, `RenderTemplateResult`, `subscribeRenderTemplate`, `TemplateListeners`
- `repo:src/data/ws-user.ts` — `subscribeUser`, `userCollection`
- `repo:src/panels/lovelace/cards/hui-card.ts` — `HuiCard`
- `repo:src/panels/lovelace/cards/hui-markdown-card.ts` — `HuiMarkdownCard`, `templateCache`
- `repo:src/panels/lovelace/cards/hui-stack-card.ts` — `HuiStackCard`
- `repo:src/panels/lovelace/cards/hui-vertical-stack-card.ts`
- `repo:src/panels/lovelace/common/directives/action-handler-directive.ts` — `actionHandler`, `actionHandlerBind`, `ActionHandlerElement`, `ActionHandlerType`, `getActionHandler`
- `repo:src/panels/lovelace/common/handle-action.ts` — `handleAction`, `ActionConfigParams`
- `repo:src/panels/lovelace/common/has-action.ts` — `hasAction`
- `repo:src/panels/lovelace/create-element/create-card-element.ts` — `tryCreateCardElement`, `ALWAYS_LOADED_TYPES`, `LAZY_LOAD_TYPES`
- `repo:src/panels/lovelace/create-element/create-element-base.ts` — `createErrorCardElement`
- `repo:src/panels/lovelace/hui-root.ts` — `HUIRoot`, `ExtraActionItem`, `UndoStackItem`, `ActionItem`, `SubActionItem`
- `repo:src/panels/lovelace/views/hui-view.ts`
- `repo:src/resources/markdown-worker.ts`
- `repo:src/resources/render-markdown.ts` — `renderMarkdown`, `RenderMarkdownParamTypes`, `RenderMarkdownType`, `worker`
- `repo:src/state/auth-mixin.ts`
- `repo:src/util/cache-manager.ts` — `CacheManager`

## Traversed packages

- `comlink@4.4.2` (package.json SHA-256 `94b1cc6b07dc642879c3690d9a4a77a27456b1c52aa49b36b8a23738fbed75f8`)
- `cssfilter@0.0.10` (package.json SHA-256 `667a127f38a17f9ef075b68c44a33e2603ebf130620963f5d318112077eff48a`)
- `home-assistant-js-websocket@9.6.0` (package.json SHA-256 `156dcc6aba886af8c9aa5ed6d3b314440fd886ceed05534104d4c886b5d3d4db`)
- `marked@18.0.5` (package.json SHA-256 `835873ede7f8ef8d7283ef40e455228d88ddf283d1160f1ef48b2b091464ea2d`)
- `object-hash@3.0.0` (package.json SHA-256 `f86b3a8a18078fbbf71ea1cf4468129e609566f860b9d93f99f63dc2543962eb`)
- `xss@1.0.15` (package.json SHA-256 `a5453f65cdf89c1f52c5decb54f9fafd4f36b9f0f6cb5934fcdacca230b5d369`)

## Boundaries

- max-depth: 1283
- package-not-allowlisted: 29
- type-only-not-followed: 612
- unresolved: 1

## Unresolved or nonliteral edges

- `npm:object-hash@3.0.0:index.js`: unresolved-import
- `repo:src/components/ha-markdown-element.ts`: nonliteral-module-specifier

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
