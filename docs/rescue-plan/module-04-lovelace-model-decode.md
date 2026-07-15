# Module 04: LovelaceCard Model - Missing Fields And Decode Robustness

Original Claude module: `4. LovelaceCard Model: Missing Fields & Decode Robustness`.

Priority: high. This enables modules 01, 05, 06, 07, 08, and 12 to work from real Lovelace config instead of ad hoc card rewriting.

## Goal

Make NativeHA's Lovelace models lossless enough for supported native cards, robust to unsupported/unknown config keys, and stable across refreshes. Avoid trying to fully type the entire Home Assistant Lovelace schema in one pass.

## Confirmed Current-Code Findings

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:111` models `LovelaceConfig` only as `views`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:115` models `LovelaceView` only as `title`, `path`, and `cards`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:123` gives `LovelaceCard` `var id = UUID()`, which is unstable across decodes.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:126` decodes only `type`, `title`, `entity`, `entities`, `cards`, `hours_to_show`, `show_forecast`, and `content`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift:167` gives `LovelaceEntityRef` a UUID-based fallback raw ID, also unstable for some object rows.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift:30` adds `nativeID` as an ad hoc workaround built from supported fields only.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:802` constructs new `LovelaceCard` values while cleaning cards, dropping any unknown fields.

Confirmed issue: current models discard Lovelace config needed by supported card renderers and make stable view/card identity harder than necessary.

## Reference Findings

- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/card.ts:7` defines base `LovelaceCardConfig` as open-ended with `[key: string]: any`, plus common metadata like `grid_options`, `visibility`, and `disabled`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/view.ts:55` includes many view fields NativeHA lacks: `icon`, `theme`, `panel`, `background`, `visible`, `subview`, `back_path`, `sections`, `header`, `footer`, and more.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts:120` defines entities-card fields such as `show_header_toggle`, `icon`, `header`, `footer`, and row-level fields.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts:424` defines markdown card fields `text_only`, `card_size`, `entity_ids`, `show_empty`, and actions.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts:466` defines history graph fields such as `show_names`, `logarithmic_scale`, `min_y_axis`, `max_y_axis`, `fit_y_data`, `split_device_classes`, and `expand_legend`.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts:635` defines weather card fields such as `show_current`, `forecast_type`, `forecast_slots`, `secondary_info_attribute`, and `round_temperature`.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts:617` defines stack cards generically as `cards: LovelaceCardConfig[]`; grid adds `columns` and `square`.

## Target Architecture

Use typed convenience fields plus raw config preservation:

- `LovelaceConfig`: `views` plus optional raw top-level object.
- `LovelaceView`: typed fields for title/path/icon/visible/subview/theme/background/panel/cards/sections/header/footer, plus raw object.
- `LovelaceCard`: typed fields for currently supported renderer needs, plus `raw: [String: JSONValue]`.
- `LovelaceEntityRef`: robust row model for either string rows or object rows, preserving raw row config.
- Stable identity should be path-based, not UUID-based:
  - View identity: `path ?? index`.
  - Card identity: `[viewIndex, cardIndex, nestedIndex...]` plus type/entity/title fingerprint only as a fallback.
  - Entity row identity: row index plus entity/ref type.

Do not make `LovelaceCard` itself randomly `Identifiable`. Either make identity explicit during traversal, or add a stable decoded/path-assigned identity in the view model.

## Fields To Add For Current Surface

History graph:

- `show_names`
- `logarithmic_scale`
- `min_y_axis`
- `max_y_axis`
- `fit_y_data`
- `split_device_classes`
- `expand_legend`
- graph entity object fields: `entity`, `name`, `color`

Entities card / rows:

- Card: `show_header_toggle`, `icon`, `state_color`, `header`, `footer`
- Row: `type`, `entity`, `name`, `icon`, `secondary_info`, `state_color`, `show_name`, `show_icon`, `tap_action`, `hold_action`, `double_tap_action`
- Row config should preserve unsupported object rows instead of silently dropping them.

Weather:

- `name`
- `show_current`
- `show_forecast`
- `forecast_type`
- `forecast_slots`
- `secondary_info_attribute`
- `round_temperature`

Markdown:

- `text_only`
- `card_size`
- `entity_ids` or `entity_id` depending on actual server shape
- `show_empty`
- action fields

Containers:

- `vertical-stack`, `horizontal-stack`, and `grid` should decode `cards`.
- `grid` should decode `columns` and `square`.
- `conditional` should preserve `card` and `conditions` for future support, even if initially rendered unsupported.

View routing:

- `icon`
- `show_icon_and_title`
- `visible`
- `subview`
- `back_path`
- `panel`
- `type`
- `sections` can be preserved raw initially if not rendered.

## Detailed Implementation Tasks

1. Add `JSONValue` raw preservation.
   - Decode every card/view into a raw dictionary.
   - Keep typed properties as computed accessors where possible to avoid duplicated decode logic.
   - Ensure unknown keys survive through model transformations.

2. Replace UUID identity.
   - Remove or ignore `LovelaceCard.id = UUID()`.
   - Introduce `LovelaceCardNode` or `ResolvedLovelaceCard` in the app layer with `path: [Int]` and `card: LovelaceCard`.
   - Update SwiftUI `ForEach` to use stable path/native ID from traversal.

3. Make entity row decoding robust.
   - String row: entity ID with raw string preserved.
   - Object row: decode common fields and preserve raw object.
   - Unsupported row object without `entity` should still be represented so the UI can show an unsupported row warning rather than dropping the config.

4. Add supported field coverage.
   - Add typed accessors or stored properties for the fields listed above.
   - Keep camelCase Swift names mapped to snake_case Lovelace keys.

5. Stop destructive card cleaning.
   - Module 03 preferences may hide or augment presentation, but `cleanCards` should not rebuild cards and discard fields.
   - Use a separate presentation filter that wraps/resolves cards without changing the decoded model.

6. Add model tests using representative live dashboard snippets.
   - Include vertical stack with nested history/weather/markdown cards.
   - Include entities card with string rows and object rows.
   - Include weather card with `show_forecast: false`.
   - Include three views with paths `default_view`, `home_3h`, and `home_12h`.

## File Ownership And Scope

Likely files to edit in future implementation:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/Models.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHACore/LovelaceModels.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/CardViews.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardView.swift`
- Tests under `/Users/jin/Documents/Computer/NativeHA/Tests/NativeHACoreTests/`

Out of scope:

- Implementing every Lovelace card type.
- Implementing Lovelace edit mode.
- Saving Lovelace config back to Home Assistant.

## Tests And Verification

Unit tests:

- Decode base card with unknown keys and assert raw keys are preserved.
- Decode card object rows and string rows.
- Decode history graph object entity refs with `name` and `color`.
- Decode weather fields including `show_current`, `show_forecast`, `forecast_type`, and `round_temperature`.
- Decode markdown fields including `text_only`, `show_empty`, and entity IDs.
- Stable path IDs remain unchanged across repeated decodes of the same config.
- Reordering cards changes path IDs in an expected way and does not reuse old identities incorrectly.

Manual QA:

- Current live dashboard still renders all supported card types.
- Unsupported card/row warnings include enough config identity to debug but do not crash.
- Switching views after module 12 does not cause cards to flicker due to UUID churn.
- History cards keep their original `hours_to_show`.

## Risks

- Trying to fully model all Lovelace schema will slow delivery. Preserve raw config instead.
- Keeping random IDs will cause SwiftUI diffing bugs and lost per-card subscription ownership.
- Rebuilding cards during filtering can silently drop new fields added by Home Assistant.

## Acceptance Criteria

- Supported card renderers can read all fields they need from decoded Lovelace config.
- Unknown card/view/row keys are preserved in raw config.
- Card and row identities are stable across refreshes.
- `DashboardViewModel` no longer reconstructs `LovelaceCard` values just to apply local preferences.
- Current live dashboard decodes without dropping configured cards or rows.

