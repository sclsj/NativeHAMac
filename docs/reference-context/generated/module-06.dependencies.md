# Dependency graph: module 06

- Fingerprint: `06316172dfefb52dbbeb1b97b0fe6eb73f554b58fbfe64699208d50768307f9b`
- Reference revision: `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd` (clean)
- TypeScript: `6.0.3`
- Nodes: 138; edges: 935; cycles: 3
- Unresolved: 0; truncated: no

## Explicit seeds

- `repo:src/common/const.ts` — `DOMAINS_TOGGLE`, `STATES_OFF`, `TIMESTAMP_STATE_DOMAINS`, `TIMESTAMP_STATE_DOMAINS_LIST`
- `repo:src/common/entity/can_toggle_domain.ts` — `canToggleDomain`
- `repo:src/common/entity/can_toggle_state.ts` — `canToggleState`
- `repo:src/common/entity/compute_domain.ts` — `computeDomain`
- `repo:src/common/entity/compute_entity_name_display.ts` — `DEFAULT_ENTITY_NAME`, `computeEntityNameDisplay`, `computeEntityNameList`, `EntityNameItem`, `EntityNameOptions`, `DEFAULT_SEPARATOR`
- `repo:src/common/entity/compute_entity_name.ts` — `computeEntityName`, `entityUseDeviceName`, `computeEntityEntryName`
- `repo:src/common/entity/compute_state_display.ts` — `computeStateDisplay`, `computeStateDisplayFromEntityAttributes`, `computeStateToParts`, `computeStateToPartsFromEntityAttributes`, `NUMERICAL_DOMAINS`, `MONETARY_TYPE_MAP`, `DATE_TIME_DOMAINS`
- `repo:src/common/entity/compute_state_name.ts` — `computeStateName`, `computeStateNameFromEntityAttributes`
- `repo:src/common/entity/device_tracker_icon.ts` — `deviceTrackerIcon`
- `repo:src/common/entity/state_color.ts` — `domainStateColorProperties`, `stateColorCss`, `stateColorProperties`, `domainColorProperties`, `STATE_COLORED_DOMAIN`
- `repo:src/common/entity/state_icon.ts` — `stateIcon`
- `repo:src/common/entity/update_icon.ts` — `updateIcon`
- `repo:src/common/translations/blank_before_percent.ts` — `blankBeforePercent`
- `repo:src/components/entity/ha-entity-toggle.ts` — `HaEntityToggle`, `isOn`
- `repo:src/components/entity/state-badge.ts` — `StateBadge`
- `repo:src/components/entity/state-info.ts` — `StateInfo`
- `repo:src/components/ha-icon.ts` — `HaIcon`, `mdiDeprecatedIcons`, `cachedIcons`, `CUSTOM_ICONS`, `chunks`, `debouncedWriteCache`, `DeprecatedIcon`
- `repo:src/components/ha-state-icon.ts` — `HaStateIcon`
- `repo:src/data/entity/entity_registry.ts` — `EntityRegistryDisplayEntry`, `EntityRegistryDisplayEntryResponse`, `EntityCategory`
- `repo:src/data/entity/entity.ts` — `OFF_STATES`, `UNAVAILABLE`, `UNKNOWN`, `OFF`
- `repo:src/data/icons.ts` — `domainIcon`, `getComponentIcons`, `getHassIcons`, `getPlatformIcons`, `getIconFromRange`, `ComponentIcons`, `resources`, `IconCategory`, `IconResources`, `CategoryType`, `PlatformIcons`, `sortedRangeCache`, `ServiceIcons`, `TriggerIcons`, `ConditionIcons`
- `repo:src/panels/lovelace/cards/hui-entities-card.ts` — `HuiEntitiesCard`, `computeShowHeaderToggle`, `migrateEntitiesCardConfig`
- `repo:src/panels/lovelace/common/entity/toggle-entity.ts` — `toggleEntity`
- `repo:src/panels/lovelace/common/entity/turn-on-off-entities.ts` — `turnOnOffEntities`
- `repo:src/panels/lovelace/common/entity/turn-on-off-entity.ts` — `turnOnOffEntity`
- `repo:src/panels/lovelace/common/handle-action.ts` — `handleAction`, `ActionConfigParams`
- `repo:src/panels/lovelace/common/has-action.ts` — `hasAction`, `hasAnyAction`
- `repo:src/panels/lovelace/components/hui-entities-toggle.ts` — `HuiEntitiesToggle`
- `repo:src/panels/lovelace/components/hui-generic-entity-row.ts` — `HuiGenericEntityRow`
- `repo:src/panels/lovelace/create-element/create-row-element.ts` — `createRowElement`, `getRowElementClass`, `ALWAYS_LOADED_TYPES`, `LAZY_LOAD_TYPES`, `DOMAIN_TO_ELEMENT_TYPE`
- `repo:src/panels/lovelace/entity-rows/hui-simple-entity-row.ts` — `HuiSimpleEntityRow`
- `repo:src/panels/lovelace/entity-rows/hui-toggle-entity-row.ts` — `HuiToggleEntityRow`
- `repo:src/panels/lovelace/entity-rows/types.ts` — `EntityConfig`, `LovelaceRowConfig`, `DividerConfig`, `SectionConfig`, `WeblinkConfig`, `CallServiceConfig`, `CastConfig`, `ButtonRowConfig`, `ButtonsRowConfig`, `ConditionalRowConfig`, `AttributeRowConfig`, `TextConfig`

## Traversed packages

- None

## Boundaries

- max-depth: 428
- package-not-allowlisted: 30
- type-only-not-followed: 304

## Unresolved or nonliteral edges

- None

> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.
