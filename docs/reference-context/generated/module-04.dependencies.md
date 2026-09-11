# Dependency graph: module 04

- Fingerprint: `46cc82de64786e77cf64f9ef8d89ae35ba765fea586db9c29e01e5c1072e52b9`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 206; edges: 2724; cycles: 3
- Unresolved: 0; truncated: no

## Explicit seeds

- `repo:src/data/lovelace/config/card.ts` — `LovelaceCardConfig`
- `repo:src/data/lovelace/config/types.ts` — `LovelaceConfig`, `fetchConfig`, `LovelaceDashboardBaseConfig`, `LovelaceRawConfig`, `LovelaceDashboardStrategyConfig`
- `repo:src/data/lovelace/config/view.ts` — `LovelaceViewRawConfig`, `computeViewIcon`, `computeViewTitle`, `LovelaceViewConfig`, `LovelaceStrategyViewConfig`, `LovelaceBaseViewConfig`, `LovelaceViewHeaderConfig`, `LovelaceViewFooterConfig`, `LovelaceViewSidebarConfig`, `LovelaceViewBackgroundConfig`, `ShowViewConfig`
- `repo:src/panels/lovelace/cards/hui-card.ts` — `HuiCard`
- `repo:src/panels/lovelace/cards/hui-entities-card.ts` — `HuiEntitiesCard`, `computeShowHeaderToggle`, `migrateEntitiesCardConfig`
- `repo:src/panels/lovelace/cards/hui-history-graph-card.ts` — `HuiHistoryGraphCard`, `DEFAULT_HOURS_TO_SHOW`
- `repo:src/panels/lovelace/cards/hui-markdown-card.ts` — `HuiMarkdownCard`, `templateCache`
- `repo:src/panels/lovelace/cards/hui-stack-card.ts` — `HuiStackCard`
- `repo:src/panels/lovelace/cards/hui-weather-forecast-card.ts` — `HuiWeatherForecastCard`
- `repo:src/panels/lovelace/cards/types.ts` — `ConditionalCardConfig`, `EntitiesCardConfig`, `GridCardConfig`, `HistoryGraphCardConfig`, `MarkdownCardConfig`, `StackCardConfig`, `WeatherForecastCardConfig`, `GraphEntityConfig`
- `repo:src/panels/lovelace/common/process-config-entities.ts` — `processConfigEntities`, `BaseEntityConfig`
- `repo:src/panels/lovelace/create-element/create-card-element.ts` — `createCardElement`, `tryCreateCardElement`, `ALWAYS_LOADED_TYPES`, `LAZY_LOAD_TYPES`
- `repo:src/panels/lovelace/create-element/create-element-base.ts` — `createLovelaceElement`, `tryCreateLovelaceElement`, `CreateElementConfigTypes`, `_createErrorElement`, `_getCustomTag`, `_customCreate`, `_lazyCreate`, `_createElement`, `createErrorBadgeElement`, `createErrorBadgeConfig`, `createErrorHeadingBadgeElement`, `createErrorHeadingBadgeConfig`, `createErrorCardElement`, `TIMEOUT`
- `repo:src/panels/lovelace/create-element/create-row-element.ts` — `createRowElement`, `ALWAYS_LOADED_TYPES`, `LAZY_LOAD_TYPES`, `DOMAIN_TO_ELEMENT_TYPE`
- `repo:src/panels/lovelace/entity-rows/types.ts` — `LovelaceRowConfig`, `EntityConfig`, `DividerConfig`, `SectionConfig`, `WeblinkConfig`, `CallServiceConfig`, `CastConfig`, `ButtonRowConfig`, `ButtonsRowConfig`, `ConditionalRowConfig`, `AttributeRowConfig`, `TextConfig`
- `repo:src/panels/lovelace/hui-root.ts`
- `repo:src/panels/lovelace/views/hui-masonry-view.ts` — `MasonryView`, `getColumnIndex`
- `repo:src/panels/lovelace/views/hui-view.ts` — `HUIView`

## Traversed packages

- None

## Boundaries

- max-depth: 1635
- package-not-allowlisted: 25
- type-only-not-followed: 832

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
