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

The authoritative schema references for this module are `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/card.ts`, `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/view.ts`, and the supported-card interfaces in `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/cards/types.ts`. Every important field/default derived from them needs a semantic decoding test; a rendered card is not evidence that raw configuration survived.

### Unit tests

Add `Tests/NativeHACoreTests/LovelaceModelDecodingTests.swift` with checked-in synthetic JSON under `Tests/NativeHACoreTests/Fixtures/Lovelace/`. Keep fixture timestamps absent or fixed and replace real entity IDs/secrets with stable test values.

Use at least these fixtures:

- `representative-dashboard.json`: views `default_view`, `home_3h`, and `home_12h`; entities cards with string and object rows; numeric and timeline history cards (including entity `name`/`color`); weather with forecast disabled; markdown; vertical/horizontal/grid nesting; and a conditional card preserved for future rendering.
- `unknown-fields.json`: unknown top-level, view, card, action, entity-row, `grid_options`, visibility, header/footer, and nested keys with arrays, objects, booleans, numbers, nulls, and strings. Assert recursive raw-value equality after decode and presentation filtering.
- `malformed-configurations.json` (or separate one-case fixtures): missing/unknown card type, missing entity, unsupported object row, null optional values, wrong scalar/container types, truncated JSON, empty views/cards, and a deeply nested but bounded stack. Assert the documented throw, skip, or invalid/unsupported-placeholder outcome for each case; do not silently drop an entire valid sibling list.

Cover typed accessors and snake_case mapping for every field in **Fields To Add For Current Surface**. Add explicit tests that `hours_to_show` remains per card through nested traversal and preference application, `show_forecast: false` is distinguishable from absence, unknown keys survive, and decoded models never introduce UUID/random fallback values.

The existing narrowly scoped `XCTExpectFailure` for per-card `hours_to_show` in `Tests/NativeHAMacTests/GraphRenderingTests.swift` may document the current known gap while the implementation is still absent. Remove that expectation as part of the change that stops overwriting decoded hours; do not turn it into a permanent expected failure.

Decode identical bytes twice and assert resolved view/card/row paths match. Then insert, remove, and reorder siblings and assert the documented path-identity behavior without accidental reuse. Because pure index paths intentionally change after reorder, also verify any fallback fingerprint is deterministic and does not contain Swift's process-randomized `hashValue`.

### Integration tests

Add `Tests/NativeHAMacTests/LovelaceRenderingIntegrationTests.swift` to pass the representative and malformed fixtures through decode -> stable traversal -> optional module-03 preference wrapper -> `CardRenderer`. Assert supported card counts/order, unsupported placeholders, preserved original models, independent history hours, and stable SwiftUI IDs across identical refreshes. A late config refresh must update only the node whose semantic input changed.

If a malformed card is intentionally rejected at the top-level decoder rather than represented, test the surrounding dashboard's explicit error/fallback state instead. This choice is an implementation-time hypothesis to resolve; whichever policy is selected must be consistent and covered rather than inferred from a screenshot.

### GUI rendering and visual regression

Extend `LovelaceRenderingIntegrationTests.swift` (or the existing `GUIRenderingAndPerformanceTests.swift`) with `@MainActor` offscreen renders for UI states that this decode module directly changes:

- An unknown card fallback at `496 x 150` points and an unsupported entity-row/fallback card at `496 x 210` points.
- A supported vertical stack decoded from JSON at the real dashboard column width, `496 x 640` points, containing nested entities, history, weather, and markdown cards. Use `360 x 640` as the narrow variant to expose wrapping/clipping caused by nested config. Do not require grid/conditional screenshots until those renderers themselves enter scope.
- Two otherwise identical refresh renders to catch layout churn from unstable identity; retain semantic identity assertions because pixel equality alone cannot prove lifecycle correctness.

NativeHA targets macOS 12 with Swift 5.6/Xcode 13.4.1. Do not use SwiftUI `ImageRenderer`. Follow [`../visual-testing.md`](../visual-testing.md): host SwiftUI in `NSHostingView` inside a small offscreen AppKit window and capture through `bitmapImageRepForCachingDisplay(in:)` plus `cacheDisplay(in:to:)`. Fix dark appearance/color scheme, logical size, display scale `2`, locale/timezone where production APIs permit, and all fixture data. Tests touching `NSApplication`, SwiftUI state, or `DashboardViewModel` run on the main actor and use bounded settlement rather than arbitrary sleeps.

Always write inspectable PNGs such as `lovelace-unknown-card.png`, `lovelace-unsupported-row.png`, `lovelace-nested-496.png`, and `lovelace-nested-360.png` to `.build/render-artifacts/`. Before comparison, assert a valid PNG signature, exact pixel dimensions (`logical size * 2`), nonblank output, expected card/text/accent regions, and settlement past any loading state.

Do not mechanically approve current NativeHA output. Compare each artifact manually with the same fixture/state in `/Users/jin/Documents/HA/hass-frontend` or the live reference frontend; only reviewed PNGs go in `Tests/NativeHAMacTests/ReferenceImages/`. Approved references use tolerant pixel comparison and document the macOS version. `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1` may become required in CI only after this reference set is complete. Intentional changes require review of actual, expected, and preferably diff artifacts before baseline replacement.

### Animation and interaction

No animation or gesture behavior is introduced by model decoding, so animation keyframes and synthetic trackpad events are unnecessary. Stable-identity refresh behavior must be tested with deterministic before/after model state and explicit refresh renders, not real-time sleeps. Any card-specific animation belongs to that renderer's module.

### Performance and lifecycle

Add `Tests/NativeHACoreTests/LovelaceModelPerformanceTests.swift` using a deterministic large fixture of 10 views x 50 cards (500 total cards), including nested stacks and mixed row shapes. Generate/serialize it before the measured block, then:

- Measure cold JSON decode and typed/raw model construction separately from warm traversal/presentation transformation.
- Measure repeated refresh decoding plus stable-node resolution, consuming a deterministic count/fingerprint so work cannot be optimized away.
- Measure transformation with module-03 preferences separately from decoding and verify the source model remains unchanged.
- Exercise repeated decode/discard and config replacement cycles; assert no unbounded retained decoded models, resolved traversal nodes, or random-ID cache entries remain after replacement.

Use `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, warm caches before warm-path measurement, and store XCTest baselines rather than tight machine-dependent millisecond limits. Xcode 13.4.1 has no `XCTHitchMetric`; true scroll/flicker/event-to-frame measurements must wait for an XCUITest app target under newer Xcode. Signposts are optional only around an instrumented decode/transform interval.

### Manual QA

- Compare the representative fixture with its hass-frontend rendering and verify nested order, fallback visibility, card/view metadata effects, and each history card's configured `hours_to_show`.
- Load the current live dashboard and confirm every supported card/row is present; unsupported card/row warnings identify the failing config without exposing secrets or crashing.
- Refresh and switch views repeatedly after module 12. Inspect for UUID-related flicker, lost card state, duplicate subscriptions, wrapping/clipping, and stale cards. Manual observation is required for conformance but does not replace semantic decode/identity or lifecycle assertions.

## Risks

- Trying to fully model all Lovelace schema will slow delivery. Preserve raw config instead.
- Keeping random IDs will cause SwiftUI diffing bugs and lost per-card subscription ownership.
- Rebuilding cards during filtering can silently drop new fields added by Home Assistant.
- A permissive malformed-config fallback can conceal a real schema regression, while an all-or-nothing decoder can discard valid sibling cards. Document and test recovery at each nesting boundary.
- Snapshot fixtures containing random UUIDs, process-randomized hashes, current dates, or locale-dependent labels will produce nondeterministic baselines. Stable path/fingerprint and fixed environment checks must run before approval.
- Large-fixture measurements can accidentally include fixture generation or downstream bitmap rendering. Decode, transformation, and renderer performance must remain separate.
- Tolerant pixel references can show fallback layout regressions, but cannot prove raw-key preservation, stable identity, accessibility, subscription cleanup, or performance.

## Acceptance Criteria

- Supported card renderers can read all fields they need from decoded Lovelace config.
- Unknown card/view/row keys are preserved in raw config.
- Card and row identities are stable across refreshes.
- `DashboardViewModel` no longer reconstructs `LovelaceCard` values just to apply local preferences.
- Current live dashboard decodes without dropping configured cards or rows.
- Representative, unknown-field, and malformed fixture suites cover every currently supported typed field, recursive raw preservation, nested sibling recovery, per-card hours, and deterministic path/fingerprint identity.
- Decode-to-render integration produces reviewed artifacts for unknown/unsupported fallback and `496`/`360`-point nested layouts, with PNG validity/region checks and optional approved macOS-versioned tolerant references.
- The 500-card fixture has separate clock/CPU/memory baselines for cold decode, warm traversal/transformation, and repeated refresh; repeated disposal does not retain decoded models or resolved traversal nodes.
- No test treats a screenshot as proof of data correctness, raw preservation, stable identity, lifecycle cleanup, accessibility, or performance.
- Trackpad/scroll hitch and true event-to-frame testing are explicitly deferred because Xcode 13.4.1 lacks `XCTHitchMetric` and the current package has no XCUITest app target.
