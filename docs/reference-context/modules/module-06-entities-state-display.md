---
schema: nativeha-evidence/v1
module: "06"
title: Entities cards, entity rows, state display, icons, and supported actions
plan: ../../rescue-plan/module-06-entities-state-display.md
status: complete
contract_revision: 2
depends_on: ["04", "05"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: 9291da336d2f068c39c4924fed3add4c52c27f85
graph_file: ../generated/module-06.dependencies.json
graph_fingerprint: 82da28fe00be690afdec34ab491962cfbf857c3c2b1a14cfff1f607d0fba171f
last_researched: 2026-08-31
last_implemented: 2026-09-01
last_verified: 2026-09-01
last_validated: 2026-09-11
---

# Module 06 evidence packet

2026-09-11 anchor refresh: the shared dashboard bootstrap and its tests changed; see [Module 05 consolidation](module-05-dashboard-viewmodel-state.md#2026-09-11-bootstrap-consolidation) for validation and limits. This module's contract revision is unchanged; older verification entries below retain their original revision-specific evidence.

## Scope delta

Module 06 consumes, but must not alter, Module 04's raw JSON/source-path identity and Module 05's one MainActor lifecycle tail, authoritative entity snapshot, locale/precision metadata, and service-controller authority. It turns entities cards into a bounded native presentation layer; it does not start a card subscription, create an owner/feed/task, add a server fetch, change a service transport, or implement Modules 07/10/11.

Before this implementation, the app rendered every usable row as a `Button` with a crude `DomainIcon`, collapsed duplicate default-view rows in the presentation layer, formatted state/name in `DashboardViewModel`, and showed a header switch solely when more than one current row is toggleable. The verified Module 06 diff closes those implementation gaps without making them approved product deviations or adding a new owner, fetch, cache, persistence key, or typed configuration surface.

Live read-only evidence on 2026-08-31: the fixed deployment supplied 280 authoritative states, 276 display-registry entries (74 `dp` precision entries), frontend language `en`, three views, 22 top-level/31 recursive cards, and 66 rows. This is deployment evidence only: contracts retain the existing locale/timezone metadata path and must not hard-code English as policy. The pre-Module 06 Swift decoder discarded compact registry `ic`, so the research audit could not claim that the other 202 entries lacked icons. The verified implementation now carries `ic` from the already-fetched response without adding a command.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering, ownership, and error rule | Evidence | Swift owner / verification |
|---|---|---|---|---|---|
| C06-01 | Decode/resolve entities-card rows | Preserve every raw string and object row through Module 04. A string is an entity row; an object exposes current typed fields (`entity`, `type`, string `name`, `icon`, `secondary_info`, `state_color`, `show_name`, `show_icon`, and three actions) while its complete raw object remains the canonical extras store. The Module 06 adapter additionally parses structured `name` from raw without rebuilding it. Unsupported type/options/extras never disappear or coerce. | No Module 06 decoder may rebuild raw `JSONValue`, use array/presentation indices as identity, or turn unknown fields into defaults. A non-object/non-string or malformed required scalar field remains the current local diagnostic placeholder. A diagnostic caused only by non-string `name` is nonfatal to the row: use the structured-name matrix, diagnose only unsupported items, and render all other row semantics. Blank entity strings and objects without a supported renderer remain unsupported rows. | C04-01..03; HF-01..05/HF-08 | `LovelaceEntityRef`/`LovelacePresentationRow` unchanged; pure raw-name adapter; model fixtures. |
| C06-02 | Two configured rows name the same entity; insertion/reorder/refresh; synthetic rows | Every source row remains independently visible and has its exact `LovelaceResolvedIdentity` (path + canonical raw semantic value), even if entity IDs and options match. Source order is preserved. | Default-view filtering still removes only approved hidden source entities. Synthetic extras are inserted only when their entity is not already a kept source row; they use the existing synthetic path. Never collapse two source rows, re-key a source row, or disturb Module 04/05/12 owner reconciliation. | C04-04..08; current `LovelacePresentationTransformer` audit | `LovelacePresentation.swift`; duplicate/refresh/reorder integration tests. |
| C06-03 | State/name presentation for a present or missing row entity | A configured string `name`, including `""`, is exact. With no configured name, `attributes.friendly_name` wins whenever the key exists (`null` becomes empty and a scalar is stringified); otherwise use the object ID with underscores replaced by spaces. Structured names support exact text and state-derived entity items per the matrix below. Context-dependent or invalid items alone are diagnosed/omitted; they never invalidate the row. Missing state, `unknown`, and `unavailable` are three distinct presentations. | Presentation is a pure snapshot of `states`, registry precision/icons, locale preferences, server timezone, frontend language, and optional injected deterministic clock. It subscribes to nothing and has no delayed update/task. Only `Missing entity`, `Unknown`, `Unavailable`, and `Never triggered` are approved verified-`en` labels; every other translation-dependent state remains the exact raw HA state. Missing state never invokes actions. | HF-02, HF-06..08, HF-17; Module 05 state ownership | New pure formatter/name resolver; exact structured-name/language matrix tests. |
| C06-04 | Format number, unit, duration, date/time, timestamp, enum, and raw state | Numeric formatting applies when HA attributes imply numeric, for `counter`/`input_number`/`number`, or a numeric sensor device class. Registry `dp` fixes min/max fractional digits; otherwise integral state plus integral `step` is integer; otherwise preserve a string numeric value's fractional precision. Monetary uses currency formatting; duration `min`/`h`/`d`, date/time domains, timestamp domains, and sensor timestamp/uptime device classes take their corresponding locale/timezone paths. Unit separation is exact: degree never has a blank; percent uses the language allowlist below; prime and every other unit have one blank. All translation-dependent non-sentinel states fall back to the exact raw state. | Use existing `HAFrontendLocalePreferences` and `HAConfig.timeZone`: `time_zone=server` uses a valid server IANA zone; otherwise current zone. Time-only/date-only/input datetime values are timezone-agnostic. Foundation is the native formatter; it must preserve semantic value/precision/unit even where its localized punctuation differs from web `Intl`. No translation fetch, settings, or `AppConfig` value is added. | HF-06; HF-10..17; Module 02 C02-08 | New formatter, reuse existing graph locale resolver only as a shared policy reference; unit tests with explicit locale/zone/now. |
| C06-05 | Resolve an entity icon | Decode compact `ic` into `HAEntityRegistryDisplayEntry.icon`, install an entity-ID/icon dictionary at the same accepted bootstrap generation as `dp`, and pass it into the pure presentation snapshot. Resolution precedence is row `icon`, carried registry `ic`, state `attributes.icon`, state-specific rule, device-class/domain fallback, then neutral fallback. Exact requests remain semantic provenance. The approved backend is the exact bounded SF table; an unlisted `mdi:`/custom identifier is never passed to `Image(systemName:)`, discarded, or fetched. | Reuse the existing `fetchEntityRegistryDisplay` response; add no command/fetch/subscription/cache. Decode only `ei`, `dp`, and `ic`; do not infer area/device/name context from ignored compact fields. An unsupported identifier gets deterministic fallback plus a visible/accessibility diagnostic. Every preferred SF name must pass the macOS 12 runtime availability gate below. | HF-08..10, HF-18..20, HF-24; existing `DomainIcon` | `Models.swift` registry decode, ViewModel accepted-bootstrap carry/reset, pure icon resolver and renderer; exact decode/generation/fallback tests. |
| C06-06 | Card or row `state_color` | Effective configuration is row Boolean first; otherwise a present card Boolean propagates only when the row has no explicit `type` or has `type: conditional`; otherwise it is absent. If absent, only `light` defaults state coloring on. When coloring is on, unavailable uses the unavailable role, numeric battery uses high `>=70`, medium `>=30`, low `<30`, and a reference-colored domain uses its active/inactive role. When coloring is off, normal foreground wins even for unavailable. | Semantic macOS tokens map the reference roles; never copy CSS constants or use color to infer service eligibility. Unknown is inactive. The exact active-state exceptions are pinned in the state-color matrix below. | HF-01, HF-11, HF-21 | Presentation enum + exact matrix GUI/semantic tests. |
| C06-07 | Decide row/header power presentation and dispatch | Header configured intent follows `computeShowHeaderToggle` exactly: when `title !== undefined` (including `""`) and `show_header_toggle === undefined`, require at least two configured entity rows in `DOMAINS_TOGGLE`; otherwise coerce the explicit flag. Actual candidates, checked state, rendered control, and safe dispatch are the separate matrix below. An implicit/explicit toggle row shows enabled power for safe `on`/`off`, disabled power for `unknown`/`unavailable`, and formatted text otherwise. | Invocation preserves complete C05-08/D05-05 behavior: gate through installed caller, accepted lifetime, present/available state and incompatible in-flight token **before** optimistically publishing the target state with all attributes/context/timestamps retained; then start the generation/action-token-owned REST task. Header uses reference-derived static routing and per-entity inherited owners, never an aggregate task. No service-catalog/bootstrap fetch is added. | HF-01, HF-04, HF-15, HF-22; C05-08/C05-10/D05-05 | Pure intent/candidate/routing policy + existing ViewModel/controller; exact optimistic/route/ID/order/cancellation tests. |
| C06-08 | Tap/hold/double action config | Preserve all three raw action objects and classify them without payload logging. For tap only: absent means details for the row entity; `more-info` means details for `action.entity` or the row entity; `none` means no primary target; `toggle` uses C06-07 only when safe. A confirmation wrapper or any other/malformed action is unsupported. Hold and double-tap are preserved but not recognized in this stage, including when their nested action would otherwise be supported. | Unsupported configured actions never fall through to details or a service. The row remains visible, loses only the unsupported primary activation, and shows one non-focusable warning accessory whose tooltip/accessibility text lists the unsupported gesture/action names. Do not add gesture timers, navigation, URL opening, perform/call-service, assist, DOM events, confirmation dialogs, or new service authority. | HF-02, HF-16, HF-23; existing `openDetails`/power facade | Exact action/focus matrix + no-call GUI/accessibility tests. |
| C06-09 | `secondary_info` / IDs | Support `entity-id`, `last-changed`, `last-updated`, `last-triggered`, `position`, `tilt-position`, `brightness`, and `state`. Position/tilt render when their attribute exists, including numeric zero. Brightness renders only for a positive numeric value as rounded `(value / 255) * 100` percent; zero/missing/nonpositive/nonnumeric renders no line. Missing `last-triggered` presents verified-`en` `Never triggered`; other absent required values render no line. | Timestamp secondary info supplies exact localized date/time accessibility plus native relative time without a model timer. The existing registry response now carries only `ei`/`dp`/`ic` into NativeHA; `area` remains absent and no area/device fetch is added. Generic rows preserve but ignore `show_name`/`show_icon`. Exact visible/accessibility strings are in the matrix below. | HF-02; C02-08 / C05 metadata boundary | Pure secondary resolver, row rendering and fixed-zone GUI/accessibility tests. |
| C06-10 | Keyboard, focus, lifecycle, state bursts, disappearance | Exact keyboard order is enabled header switch, then each source row's enabled primary target followed by its enabled row control. Static labels, warning accessories, missing/unsupported rows, and disabled controls are excluded from keyboard focus but remain in the accessibility tree with label/value/help. Return/Space activates a primary `Button`; Space toggles a focused `Toggle`. `tap_action:none` or unsupported tap removes only the primary target. | Use sibling targets; never nest a `Button` around a `Toggle`. Presentation recalculates synchronously from the published entity dictionary and owns no observer/feed/task/timer. Module 05 stop/retry/reconnect revokes service authority before invocation; late service results remain controller-gated. | C05-01..10; HF-02/HF-04/HF-23 | Hosted AppKit focus/accessibility matrix and lifecycle integration tests. |
| C06-11 | Any Module 06 change | Fixed token/base URLs, profile/settings absence, locale/bootstrap commands, Core Graphics renderer/range/history/cache, Module 04 raw identity, Module 05 owner tail/service safety, and Module 12 navigation selection remain unchanged. | Stop immediately if implementation needs a new icon/translation/area fetch, typed `AppConfig` value, profile/persistence decision, WebSocket/REST service redesign, graph work, or specialized climate/fan/weather-row semantics. | deviations/configurability; C04/C05/C12 | Static scope/policy scans and inherited full suite. |

## Source anchors

All frontend anchors are at clean hass-frontend revision `dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd`; all exact graph node SHA-256 values are in the generated graph.

| ID | Source, stable symbol | SHA-256 | Relevance |
|---|---|---|---|
| HF-01 | `src/panels/lovelace/cards/hui-entities-card.ts`, `computeShowHeaderToggle`, `_renderEntity` | `ae43e83ae41141f96751b0f15fd107a1af38a81d693ddfe8a4cbead56cb370c5` | Header default/explicit semantics and exact card `state_color` merge. |
| HF-02 | `src/panels/lovelace/components/hui-generic-entity-row.ts`, `HuiGenericEntityRow` | `2d61fd431696745352fe5268573b5b0ddce6e72baebdc473958c19abadd764f7` | Missing row, name, secondary values, focus/action affordance. |
| HF-03 | `src/panels/lovelace/entity-rows/hui-simple-entity-row.ts`, `HuiSimpleEntityRow` | `9544418477ce9e614cbaf94d34f5b828e698ad0cfd9190b98f8d205acc501753` | Timestamp/simple row display. |
| HF-04 | `src/panels/lovelace/entity-rows/hui-toggle-entity-row.ts`, `HuiToggleEntityRow` | `fee54eccaa59adaa3c0388e0914f6e7cf0e392dd5b3f1e8f6177ecf107ba1372` | Toggle/text and unknown/unavailable presentation. |
| HF-05 | `src/panels/lovelace/entity-rows/types.ts`, row config types; `src/panels/lovelace/create-element/create-row-element.ts`, `DOMAIN_TO_ELEMENT_TYPE` | `4a6479d6d7ffea3b402c668b5fb2b9689f04875e302fedec1dd3ad1dac42443c`; `9029d7b88e9438ae453b868435c25c26e69081982e23b4c7a6c952b358111752` | Exact explicit/domain row factory matrix. |
| HF-06 | `src/common/entity/compute_state_display.ts`, `computeStateDisplayFromEntityAttributes` | `6ae38ab3fbf1f09f3461dbcc9746d8525e9339e268ec6d22850d778f17f89537` | Display decision tree. |
| HF-07 | `src/common/entity/compute_state_name.ts`, `computeStateNameFromEntityAttributes`; `src/common/entity/compute_entity_name.ts`, `computeEntityName` | `541b48f463bee7304ec4a1c07461984e9f15f47a4237d9590bb175409e19113c`; `f7cf9d38c6600d8348041a792b60d88b6908bd5d1921c6e29355fcc3903c446f` | Friendly/object-ID and registry/device name fallback. |
| HF-08 | `src/common/entity/compute_entity_name_display.ts`, `computeEntityNameDisplay` | `289301f8a2dc1184ebfaa637e66cf00d099036533ebefbac39991a1f1397144e` | String/structured configured-name semantics. |
| HF-09 | `src/common/entity/state_icon.ts`, `stateIcon`; `device_tracker_icon.ts`; `update_icon.ts` | `8be33a2888ef35df6bbf328d8e3221aa3d0f2a0ea6274a7e19b1b3b0716f710a`; `ce550472374c9a663996f4c2199e61945e6980eddf476c4162e272917e2dbeb0`; `4814a4e9f3ecd10382fb5f2db6862f986cbf481203084a47c03d9e54ad4e038b` | State-aware icon selection. |
| HF-10 | `src/data/icons.ts`, `getEntityIcon`, `domainIcon` | `a07b3f86aaa0e6820b952c0f54161587c6696d58cc5633adb506a714f26ec48a` | Dynamic entity/platform/component icon-resource lookup. |
| HF-11 | `src/common/number/format_number.ts`, `getNumberFormatOptions`, `getDefaultFormatOptions` | `52dfeb9bd192f3cbc84466548727d98dbfcba32dcbd4ed469ef51bc6d00dee88` | Precision, trailing digits, grouping policy. |
| HF-12 | `src/common/datetime/format_duration.ts`, `formatDuration` | `b4a9407224d5d25094157fc32f82707264d5ac40691a09668a5c0fa65573813f` | Duration conversion/precision. |
| HF-13 | `format_date_time.ts`; `format_date.ts`; `format_time.ts` | `e7f688d56292516b0acd594bd45408f59a656ea584b0f6b43e09aae13bd5939d`; `292124c083d478fb9c59c0ba4b09559133fafe1673f9a80d02019430b858d101`; `0eea20bb5217bf56c6e55cfaa0d58a7e0033acce456fd3f97b99491824af9da4` | Date/time formatting. |
| HF-14 | `resolve-time-zone.ts`; `blank_before_unit.ts`; `blank_before_percent.ts`; `src/data/sensor.ts`; `sensor_numeric_device_classes.ts` | `6b33f06c955e1bf78ef23b8f2b6de37ba581dc4a8a30a355a0dda60d4f4efcae`; `1e9cea22b62875f83cd64d497e89aba6409562267552a1636a064736ac206351`; `1c2ad7a36d91e00500433195dd2a1016cde7c592364ec3c9e15b2da19a5bf586`; `0cc8d06ba496ddf8776de261aca3b5640306c76016df7e91586ad5f8b9f11131`; `6624809c273042278273c4c250aa8600f16c31eb658be9233107c1a56276f53d` | Zone, exact degree/percent/default unit spacing, numeric/timestamp sensor classes. |
| HF-15 | `src/common/const.ts`, `DOMAINS_TOGGLE`, `STATES_OFF`, `TIMESTAMP_STATE_DOMAINS` | `284e92843a5aa4f640dbaaefd5221c2a684f2a05a2079d3ed8add863baed3199` | Header candidates, transition states, timestamps. |
| HF-16 | `src/panels/lovelace/common/process-config-entities.ts`, `processConfigEntities` | `9944ea2014a25ef1cccf3624f34047a03034ca1e6fd597e1edcea68694a766fc` | String-to-object normalization without identity authority. |
| HF-17 | `src/data/entity/entity.ts`, `UNKNOWN`, `UNAVAILABLE`, `OFF_STATES` | `8b3531fdcf3c2234fd1709f0a23bcc98c6af67a9db5550ed05bc1165845446a5` | Distinct sentinel states. |
| HF-18 | `src/components/ha-state-icon.ts`, `_overrideIcon`, `_iconTask`, `_renderFallback` | `5b127bf1ace24435832c5644cd36463b6817d88a0c265d4d9d1df682e7688fb2` | Row/registry/state icon precedence and dynamic lookup. |
| HF-19 | `src/components/ha-icon.ts`, `_loadIcon` | `fe12955c221ca10a950430b28c4b9393cada37c7897d9891b0d531fb16ee29b6` | MDI/custom/catalog loading behavior deliberately bounded out. |
| HF-20 | `src/components/entity/state-badge.ts`, `_stateColor`, `willUpdate` | `f26948123e1845949d8d72ded7eb99994988415e7ea3ef383d5b909b99664498` | Override icon handoff and light-only default state coloring. |
| HF-21 | `state_color.ts`; `state_active.ts`; `color/battery_color.ts` | `2d8556053d34e46049d6129de5d027232afa7382dccab20c3ae545c1026f1162`; `9ae81c85b5523e4b1a3e7d0399ae238ef6a89b9ada810748f35c0eeda92f7d13`; `b4e82e9c9e7e7581b5b1cdd7a00c8437976326b115d94a74c38f07a75bcd8e96` | Exact semantic color roles and battery thresholds. |
| HF-22 | `hui-entities-toggle.ts`; `turn-on-off-entities.ts`; `ha-entity-toggle.ts`; `turn-on-off-entity.ts`; `toggle-entity.ts`; `can_toggle_domain.ts`; `can_toggle_state.ts` | `6ee814d3eb5491ca3967c8c5f05619c528c01fd359593bafabed460003d49d7e`; `067244f90023cc3ea8745d75638d88aed89e7d4b285f860acce775e56757ef96`; `026b6154f876ccc32f1d69fe7a2248ea74e11a8f727434470326802c54edbb1c`; `711ddabaf302d4beb9a1abfdbeabfbacac4df5861b59c9e100bf32c6d0766404`; `3c63221ac89a68b67fa036d1cea640f9e5956ebffed631b1b0e204cc04a592f4`; `d65df7e3fdee3d51ea05b9d345493dfa7e6fe67582112b20b81aed77521b4a03`; `feb3927ce5ea82711f57dde13cdd626628f4b7b5a25681ac1b0ddd924e3fe267` | Header/single-row candidate, state and service routing. |
| HF-23 | `handle-action.ts`, `handleAction`; `has-action.ts`, `hasAction`, `hasAnyAction` | `f0276cbaa278333684e31cfb56a27b37fe578ace18bebf576d7cab938c82fdfc`; `fdae56ecfe56a485528bbc75882f002b4afe3a455bb13eeef19423f9bc211466` | Default more-info, configured action universe, pointer/focus rules. |
| HF-24 | `src/data/entity/entity_registry.ts`, `EntityRegistryDisplayEntryResponse`, `EntityRegistryDisplayEntry` | `8ca09217f83a34fc78662e858393f90d269666ba9c3019be969817a77e73c6a2` | Already-fetched compact `ic` icon field and expanded registry shape. |

Verified NativeHA worktree on research commit `9435dadbea7e55bc8a84ea63b9b3f67a2c978d1e`:

- `LovelaceModels.swift` (`02bed5b336729a496c7f2a48ecdcf17956af998624076ed0835164c188a9436e`): lossless row source/config/identity;
- `LovelacePresentation.swift` (`a79e4b7f8ac7b52ba408f8063c2b4b95b734069d5134cba39857624e562d9ca1`): hidden/synthetic rows with source duplicates preserved;
- `CardViews.swift` (`a2cafc5d1ab8cd35deb271393e9816e1a252d0dd4cf044a49b70ad69f7b83ac8`): verified card/row/icon, native accessibility, and sibling focus targets;
- `EntityRowPresentation.swift` (`a9f4ea8a7959bb44e6acc19187556c547702e2ba4476344f7997331bcffb0916`): pure row/name/state/icon/color/action/secondary/power presentation;
- `DashboardViewModel.swift` (`804607628fed769f13a601546ee1ec55fcbaa1e1db0bcefdcbb88fde958a6973`): verified presentation delegation, accepted-generation registry metadata, and inherited service facade;
- `DashboardServiceController.swift` (`4c6dc0c32c346a1075239914f706c560ee85ec4de538afa6701b2b234a12af42`): caller, availability, generation and task ownership;
- `Models.swift` (`a4ebefa46477ad6caf9bf67cca14d6ed2b16ac4227d6d5b898de5cfc3f7dcd21`), `HAEntityStore.swift` (`4ae8b132f662d51926fe5b2ccbc5b749435cedb81d5292ea6db1fb519e964387`), `DashboardLifecycle.swift` (`306aa9f9c9cd8bb555a5c1f430443fa6e62eea3f54086ca4bd02d03d954370dd`), `DashboardView.swift` (`58dc1ba15d5831625c85e9d80db6d588794b3515a6c306d29b8b3c5c60c92395`), `LovelaceViewNavigation.swift` (`20cde182e49d1d9ff0a04c8c2f563bdfd3425c6cc500a721d1a6111b54e0f2ba`), and `GraphTooltipFormatting.swift` (`12e1d9bc92b425bd3ee3419577f2b9d496f094c7e52363ff738263df2690fde4`): compact registry icon decode, state metadata, lifecycle/navigation, and locale/timezone seams.

## Dependency traces and boundaries

The generated graph is [module-06.dependencies.md](../generated/module-06.dependencies.md): 138 nodes, 935 edges, three cycles, zero unresolved edges, no truncation, fingerprint `83b2f31867444282f31c97da1da732e5b401a9222792212102a9b514b4eac4ed`.

- Card/row trace: `hui-entities-card` -> `process-config-entities`/ `create-row-element` -> generic/simple/toggle row. It ends before lazy specialized row implementations: entering them would be Module 07/10/11 or another explicit row module.
- Display trace: `compute_state_display` -> numeric, duration, date/time, sensor, translation and unit helpers. They were read through their output rule; browser `Intl`/translation catalogs are a native platform boundary.
- Icon trace: `state_icon` -> tracker/update and `data/icons` catalog lookup. The latter's `frontend/get_icons` resource request is not called by NativeHA; bounded SF fallback is the documented native boundary.
- Toggle/action trace: card/header toggle -> `ha-entity-toggle` -> `turn-on-off-entity`; generic row -> `handle-action`. NativeHA stops at the current Module 05 controller/details overlay, instead of importing browser navigation/service/action semantics.
- Runtime packages are type-only for this surface. No behaviorally relevant `node_modules` execution edge was crossed; the separately verified `home-assistant-js-websocket@9.6.0` transport/state stream remains Module 02/05 ownership.

## Exact native behavior matrices

### Row selection and specialized-row boundary

Explicit `type` wins; otherwise the pinned reference `DOMAIN_TO_ELEMENT_TYPE` mapping classifies every source row exactly once. The grouped rows below are exhaustive for that mapping:

| Implicit domain input | Exact reference element type | Module 06 result |
|---|---|---|
| `_domain_not_found` and any unmapped domain, including current `binary_sensor` and `device_tracker` | `simple` | Generic shell plus formatted read-only state. |
| `alert`, `automation`, `fan`, `input_boolean`, `light`, `remote`, `siren`, `switch`, `vacuum` | `toggle` | Generic shell plus C06-07 power control. These are the only nine implicit toggle domains. |
| `sensor` | `sensor` | Generic shell plus C06-04 formatted read-only state. |
| `climate`, `weather` | `climate`, `weather` | Read-only generic shell internally marked `deferredSpecialized`; no specialized controls. Modules 10 and 07 own parity. |
| `button` | `button` | Visible unsupported-row diagnostic preserving raw identity. |
| `cover`, `date`, `datetime`, `event`, `group`, `humidifier`, `input_button`, `input_datetime`, `input_number`, `input_select`, `input_text`, `lock`, `media_player`, `number`, `scene`, `script`, `select`, `text`, `time`, `timer`, `update`, `valve`, `water_heater` | respectively `cover`, `date`, `datetime`, `event`, `group`, `humidifier`, `input-button`, `input-datetime`, `input-number`, `input-select`, `input-text`, `lock`, `media-player`, `number`, `scene`, `script`, `select`, `text`, `time`, `timer`, `update`, `valve`, `climate` | Visible unsupported-row diagnostic preserving raw identity; never reinterpret as generic or actionable. In particular, implicit `group` is a specialized `group-entity` row, not a toggle row. |
| Explicit `simple-entity` or `sensor-entity` | named row | Generic read-only shell. |
| Explicit `toggle-entity` with a domain in the static row-route table | named row | Generic shell plus safe power control. |
| Any other explicit built-in type, any custom type, missing entity/type, or malformed row | specialized/structural/custom/error | One visible unsupported-row diagnostic preserving raw identity; never reinterpret it as a generic actionable row. |

`button`, `call-service`/`perform-action`, `buttons`, `conditional`, `divider`, `section`, `weblink`, `cast`, `attribute`, and `text` therefore remain preserved but unsupported. A live occurrence is a release stop requiring its own module.

### Name, state, and secondary value matrix

| Input | Exact result |
|---|---|
| Configured string name, including empty | Exact string. |
| Name absent or `null`; `friendly_name` key exists | Scalar string form; `null` is empty. |
| No configured/friendly name | Object ID with `_` replaced by space; no title-casing. |
| `{type: "text", text: String}` | Exact text. |
| Array containing only valid text items, including empty array | Join text values with one ASCII space; empty array is empty string. |
| `{type: "entity"}` or an array containing only valid `entity`/`text` items | Each entity item uses the state-derived friendly/object-ID result above; join nonempty components with one ASCII space. No device-name inference. |
| `device`, `area`, or `floor` item | Preserve raw, omit that item, and emit a context-dependent-name diagnostic. Use remaining supported components; if none remain, use the friendly/object-ID fallback. |
| Unknown item type, nonobject item, or text item without string `text` | Preserve raw, omit the invalid item, and diagnose it. Use remaining supported components; if none remain, use the friendly/object-ID fallback. |
| Missing entity | Non-actionable missing row; verified-`en` label `Missing entity`. |
| `unknown` / `unavailable` | Distinct verified-`en` labels `Unknown` / `Unavailable`. |
| Numeric parse/date parse or any other translation-dependent state | Exact raw state, never underscore replacement or an invented English label. |

The C06-04 formatter decision order is: sentinel; numeric (attributes, numeric domain, numeric sensor class); date/input-datetime/time; timestamp domain or sensor timestamp/uptime class; raw. Registry `dp` overrides step/trailing digits. Degree (`°`) has no blank. Percent has one ASCII blank only for languages `cs`, `de`, `fi`, `fr`, `sk`, and `sv`, and no blank otherwise. Prime (`′`) and every other nonempty unit have one ASCII blank.

| Secondary input | Visible text | Accessibility label / value |
|---|---|---|
| `position`, value exists including `0` | verified-`en` `Position: <value>` | `Position` / exact scalar value |
| `tilt-position`, value exists including `0` | verified-`en` `Tilt position: <value>` | `Tilt position` / exact scalar value |
| `brightness`, positive numeric value | `<round(value / 255 * 100)> %` | `Brightness` / `<rounded> percent` |
| `brightness` missing, zero, negative, or nonnumeric | no line | no secondary accessibility value |
| `last-triggered` missing | verified-`en` `Never triggered` | `Last triggered` / `Never triggered` |

### Icon and state-color matrices

The deterministic SF backend is:

| Semantic request | SF Symbol |
|---|---|
| missing / unavailable / unknown | `questionmark.square` / `exclamationmark.triangle` / `questionmark.circle` |
| temperature / humidity | `thermometer` / `drop` |
| battery `>=70` / `>=30` / `<30` | `battery.100` / `battery.50` / `battery.25` |
| tracker `home` / other | `house` / `location` |
| sensor / binary_sensor | `gauge` / `sensor` |
| switch or input_boolean / automation | `switch.2` / `gearshape.2` |
| weather / climate / fan | `cloud.sun` / `thermometer` / `fanblades` |
| button / zone / number | `circle` / `mappin.and.ellipse` / `number.square` |
| script / select / update | `scroll` / `list.bullet.rectangle` / `arrow.triangle.2.circlepath` |
| every other domain | `circle.grid.2x2` |

The only direct configured/state icon translations are `mdi:thermometer`, `mdi:water-percent`, `mdi:humidity`, `mdi:battery`, `mdi:home`, `mdi:map-marker`, `mdi:toggle-switch`, `mdi:cog`, and `mdi:update`, mapped to the corresponding table role. Every other identifier retains exact provenance, emits the warning accessory/diagnostic, and takes the semantic fallback. No display string is used as cache or identity.

Before rendering, resolve every preferred name with `NSImage(systemSymbolName:accessibilityDescription:)` on the running macOS 12 target. If unavailable, try `circle.grid.2x2`; if that is unavailable, render a text-backed `?` placeholder with the same semantic accessibility label. The availability probe is injectable in unit tests. Release evidence must prove every table symbol resolves on the supported macOS 12 runner or takes this deterministic nonblank fallback; do not assume a symbol exists because it is present on the development OS.

| Effective state-color setting | State | Role |
|---|---|---|
| false | any | normal |
| true | unavailable | unavailable |
| true | numeric battery | high `>=70`, medium `>=30`, low `<30`; nonnumeric normal |
| true | unknown | inactive |
| true | ordinary colored domain | inactive for `off`; active otherwise |
| true | alarm / alert | inactive for `disarmed` / `idle`; active otherwise |
| true | cover/lock/valve/tracker-person | inactive for `closed`/`locked`/`closed`/`not_home`; active otherwise |
| true | lawn mower / media player / vacuum | inactive for `docked` or `paused` / `standby` / `idle`, `docked`, or `paused`; active otherwise |
| true | plant / timer / camera | active only for `problem` / `active` / `streaming` |
| true | group | active only for `on`, `home`, `open`, `locked`, `problem` |
| absent | light / every other domain | evaluate as true / normal |

The reference-colored domain allowlist is exactly `alarm_control_panel`, `alert`, `automation`, `binary_sensor`, `calendar`, `camera`, `climate`, `cover`, `device_tracker`, `fan`, `group`, `humidifier`, `input_boolean`, `lawn_mower`, `light`, `lock`, `media_player`, `person`, `plant`, `remote`, `schedule`, `script`, `siren`, `sun`, `switch`, `timer`, `update`, `vacuum`, `valve`, `water_heater`, and `weather`.

### Power, action, and focus matrices

| Header stage | Exact rule |
|---|---|
| Configured intent | If `title !== undefined` (empty string counts) and `show_header_toggle === undefined`, true only when at least two configured rows containing an `entity` have domains in `DOMAINS_TOGGLE`; otherwise `Boolean(show_header_toggle)`. State presence/availability is irrelevant here. |
| Actual candidates | From configured entity rows, retain entities currently present in the accepted state dictionary and in `DOMAINS_TOGGLE`; de-duplicate first source occurrence for native dispatch. |
| Rendered control | Configured intent must be true and actual candidates nonempty; otherwise no header control. |
| Checked | Any actual candidate state is exactly `on`; safety/in-flight status does not change the displayed checked value. |
| Safe dispatch | From actual candidates, remove missing/`unknown`/`unavailable`/no-caller/stopped/incompatible-in-flight targets; for turn-on retain states in `STATES_OFF`, and for turn-off retain states not in `STATES_OFF`; then apply the requested transition and route table. |

| Control | Static eligible domains | On route | Off route |
|---|---|---|---|
| Row | `alert`, `automation`, `cover`, `fan`, `group`, `humidifier`, `input_boolean`, `light`, `lock`, `remote`, `siren`, `switch`, `vacuum`, `valve` | `cover.open_cover`; `lock.unlock`; `valve.open_valve`; `group` uses `homeassistant.turn_on`; otherwise `<domain>.turn_on` | `cover.close_cover`; `lock.lock`; `valve.close_valve`; `group` uses `homeassistant.turn_off`; otherwise `<domain>.turn_off` |
| Header | exactly `fan`, `input_boolean`, `light`, `switch`, `group`, `automation`, `humidifier`, `valve` | `homeassistant.turn_on` per safe target currently in `STATES_OFF` | `homeassistant.turn_off` per safe target not in `STATES_OFF` |

`unknown`, `unavailable`, missing, stopped, no-caller, or in-flight targets are never eligible even where the reference web control can render them. This is the existing Module 05 safety boundary. Do not fetch `/api/services` or add a service map; the table is the complete allowlist. Header targets are de-duplicated by entity ID in first-source occurrence order before invoking; duplicate configured rows remain distinct presentation and identity owners.

Every accepted row or header power target follows inherited C05-08/D05-05 in this order: resolve the static route; call `canInvoke`; snapshot/publish the optimistic `on`/`off` state while retaining the complete attributes, context, `lastChanged`, and `lastUpdated`; then install the exact action-token task. There is no new Module 06 timer or local rollback. A later authoritative entity publication reconciles optimistic state. Service success/failure may update only the inherited service lifecycle/error after lifetime generation and exact action token validation; it never publishes entity state. Stop/cancel/late completion cannot roll back, advance, or otherwise mutate the retained entity snapshot, lifecycle, or error after the inherited generation/token gate fails.

| Gesture/config | Primary target | Invocation | Warning |
|---|---|---|---|
| Tap absent | yes | details for row entity | no |
| Tap `more-info`, no confirmation | yes when target exists | details for action entity, else row entity | no |
| Tap `none` | no | none | no |
| Tap `toggle`, no confirmation | yes only when C06-07 eligible | desired opposite safe power state | no |
| Tap malformed, confirmed, or any other action | no | none | yes |
| Hold/double absent or `none` | no additional target | none | no |
| Hold/double any other value | no additional target | none | yes |

Focus order is header control, then source order with primary before row control. Disabled controls and warnings are accessible but not keyboard-focusable.

### Bootstrap boundary

The only inputs are Module 05's state dictionary, display precision dictionary, new icon dictionary decoded from `ic` in the already-fetched registry-display response, frontend locale preferences/language, server timezone, Lovelace snapshot, and installed generation-gated service caller. Precision and icon dictionaries install/reset together only after the same current-bootstrap generation check. Module 06 adds no startup command, REST request, WebSocket subscription, service catalog, icon/translation/area/device registry fetch, cache, persistence key, profile, or `AppConfig` surface.

## Native mapping and exact implementation handoff

| Contracts | Permitted production path | Owner/change |
|---|---|---|
| C06-01, C06-03..09 | New `Sources/NativeHAMac/EntityRowPresentation.swift` | Pure `EntityRowPresentation`, display/name/icon/color/action/secondary/eligibility/routing resolvers. Inputs are snapshot values; no observation/network/task. |
| C06-02 | `Sources/NativeHAMac/LovelacePresentation.swift` | Preserve source duplicates; retain hidden filtering and source-path identities; skip only redundant synthetic insertion. |
| C06-06..10 | `Sources/NativeHAMac/CardViews.swift` | Render semantic presentation data, independent row/toggle focus targets, header rule, local missing/unsupported fallback. |
| C06-03..10 | `Sources/NativeHAMac/DashboardViewModel.swift` | Delegate compatibility display APIs and expose exact existing details/service calls with table-derived domains/services. Do not add a tail/task/observer. |
| C06-05 | `Sources/NativeHACore/Models.swift` | Add optional `icon` decoded from `ic` to `HAEntityRegistryDisplayEntry`; no other compact registry field and no fetch change. |
| C06-01..10 | `Tests/NativeHAMacTests/EntityRowPresentationTests.swift` (new), `EntitiesCardIntegrationTests.swift` (new), `EntitiesCardRenderingTests.swift` (new), `EntitiesCardPerformanceTests.swift` (new), `LovelacePresentationTests.swift`, `DashboardOrchestrationTests.swift`, `DashboardServiceControllerTests.swift`, `DashboardBootstrapLifecycleTests.swift`; `Tests/NativeHACoreTests/LovelaceModelTests.swift`, `HomeAssistantWebSocketConnectionTests.swift` | Exact semantic, registry decode/carry, integration, GUI, performance, identity and inherited-safety evidence. |

These five production paths and ten test paths are the complete allowlist. `DashboardServiceController.swift` and `LovelaceModels.swift` are read-only dependencies, not permitted edits. Do not edit WebSocket, REST, `AppConfig`, graph rendering/scheduling/history, navigation persistence, specialized climate/fan/weather/detail code, package configuration, or reference sources.

Implementation sequence:

1. Add registry `ic` decode/accepted-generation carry tests and pure presentation/formatter tests, then implement `Models.swift`, the ViewModel dictionary seam, and the pure file without adding a bootstrap command.
2. Repair source-duplicate presentation without changing hidden/synthetic policy, and prove Module 04 identity and Module 12 selection/history ownership still hold.
3. Replace `EntitiesCard`/`EntityRow` rendering and delegate old display helpers. Use only existing details/service calls.
4. Add integration, hosted GUI/accessibility, performance, and lifecycle coverage; run inherited 02/04/05/12/09 gates and a fresh verifier.

## Implemented diff and independent-verification evidence

The accepted implementation is exactly eleven files on top of research commit `9435dadbea7e55bc8a84ea63b9b3f67a2c978d1e`:

- production: `Sources/NativeHACore/Models.swift`, `Sources/NativeHAMac/EntityRowPresentation.swift` (new), `Sources/NativeHAMac/CardViews.swift`, `Sources/NativeHAMac/DashboardViewModel.swift`, and `Sources/NativeHAMac/LovelacePresentation.swift`;
- tests: `Tests/NativeHACoreTests/LovelaceModelTests.swift`, `Tests/NativeHAMacTests/DashboardBootstrapLifecycleTests.swift`, `Tests/NativeHAMacTests/EntityRowPresentationTests.swift` (new), `Tests/NativeHAMacTests/EntitiesCardIntegrationTests.swift` (new), `Tests/NativeHAMacTests/EntitiesCardRenderingTests.swift` (new), and `Tests/NativeHAMacTests/EntitiesCardPerformanceTests.swift` (new).

Exact diff inspection found no WebSocket, REST client, service-controller, `AppConfig`, history, graph, navigation-persistence, package, reference-source, or durable-decision edit. The new presentation layer is pure and synchronous; the only bootstrap delta carries `ic` beside `dp` from the already-issued registry-display response at the existing accepted-generation install point.

The fresh independent verifier returned **GO** for C06-01 through C06-11 after two P1 corrections: every implicit reference-specialized domain is now visible unsupported except the literal climate/weather deferred shells, and same-entity row-domain versus header-`homeassistant` equivalent power routes exclude one another in both directions before optimism/invocation while unrelated entity concurrency remains available. Evidence on 2026-09-01:

- focused Module 06 suites: 27 executed, 27 passed, zero failure;
- full debug suite: 260 executed plus three intentional opt-in skips, zero failure, 84.98 seconds;
- release compatibility: PASS on macOS 12.6.7 with Swift 5.6.1 and Xcode 13.4.1;
- macOS-12 symbol probe: every preferred symbol resolved except `sensor`; that request took the verified nonblank neutral `circle.grid.2x2` fallback;
- GUI/accessibility: hosted dark-Aqua 2x captures passed at 496 and 320 points. The 992x1040 PNG is 96,231 bytes and the 640x1040 PNG is 83,188 bytes. Manual inspection confirmed nonblank semantic icons, long-name truncation, distinct unknown/unavailable/missing rows, disabled and enabled switches, preserved duplicate rows, and the visible unsupported-icon warning. Native sibling targets, key-view order, Return/Space activation, values, help, and disabled-control exclusion passed deterministic AppKit assertions;
- performance: 500 mixed-row cold/warm presentation and 100-of-500 update measurements consumed clock/CPU/memory results with `cache=none`; Module 06 adds no cache. There is no stored machine baseline yet, a recorded non-blocking release limitation;
- lifecycle: accepted-bootstrap precision/icon install, rejected/late bootstrap exclusion, stop/reset, state-burst recomputation, source identity, stopped/no-caller/unavailable gates, exact action-token ownership, and same-entity power-family mutual exclusion passed without a formatter owner, task, observer, timer, subscription, or aggregate header owner;
- authorized read-only live smoke: 31 recursive cards and 66 rows matched the fixed deployment; no service call, state-changing call, or persistent navigation mutation was made;
- migration/release scope: migration remains N/A because no persistence, configuration, bootstrap-command, or raw-Lovelace schema changed.

The two current PNGs were manually inspected against the packet's semantic matrix. A repeated browser side-by-side capture and an approved stored OS-labelled pixel baseline were not produced; this is non-blocking because the bounded native SF-symbol presentation is an approved staged deviation and the deterministic visual/accessibility assertions passed. It remains a limitation for later broader visual-parity work, not an unresolved Module 06 behavior or migration question.

## Decisions and native deviations

| ID | Decision | Allowed reason / preserved semantics | Status |
|---|---|---|---|
| D06-01 | Use the exact bounded SF-symbol/MDI-translation table, not MDI rendering or `frontend/get_icons`. | Module 06 rescue plan explicitly stages SF Symbols and excludes full MDI. Raw configured identity, precedence, visible diagnostics and deterministic semantic fallback prevent silent loss. | resolved; test every mapping/fallback/provenance value. |
| D06-02 | Use Foundation locale/timezone/number/date formatters. | Native convention; retain the existing frontend preference/server-zone inputs, number precision, value, unit, date/time and duration meaning. Foundation punctuation/relative-time rendering may differ from browser `Intl`. | resolved; fixed locale/zone oracle. |
| D06-03 | Header service dispatch excludes unavailable/unknown/missing/no-authority/in-flight entities while preserving inherited optimistic state publication. | Existing C05-08/D05-05: gate before optimism; retain full accepted state context; authoritative entity publication reconciles; service completion is generation/token gated and never rewrites entity state. | resolved; exact target/optimism/late-result tests. |
| D06-04 | Support tap default/details/none and safe static-table toggle; preserve but do not recognize hold/double or other tap actions. | Module 06 rescue plan explicitly limits runtime actions to existing native support. Unsupported values are visible/diagnostic and never silently substituted. | resolved; exact matrix/no-call tests. |
| D06-05 | Carry `ic` alongside `dp` from the existing registry-display response, but add no `area` value. | `ic` is already in the same response and needs only typed decode/carry; area/device context requires fields/registries intentionally not installed in the native bootstrap. | resolved bounded decode; no new command. |
| D06-06 | Render current climate/weather entity rows as non-interactive deferred-specialized shells; reject every other unsupported explicit/specialized row visibly. | Modules 07/10 own those specialized semantics; the exact factory classification and raw Module 04 identity remain intact. | resolved staged boundary; release-stop on a new live specialized type. |
| D06-07 | Limit verified-English literals to `Missing entity`, `Unknown`, `Unavailable`, and `Never triggered`; retain raw HA state for every other translation-dependent value. | The fixed live deployment reports `en`, while Module 06 is forbidden to add translation bootstrap. No undefined partial localization allowlist remains. | resolved for current deployment; language change is a stop rule. |

No typed configuration, token/bootstrap, profile/settings, persistence, icon fetch policy, service safety policy, graph/range/history, or navigation product question remains unresolved.

## Validation matrix satisfied by implementation and verification

### Offline deterministic

- Decode string/object/malformed/unknown rows and every structured-name matrix case; assert raw structural equality, extras preservation, all action fields, explicit false/null distinctions, source/synthetic duplicate identities, reorder/replacement, and no source reconstruction.
- Decode registry `ic` absent/present beside `dp`; prove accepted bootstrap carries both dictionaries, rejected/late bootstrap carries neither, and stop/replacement resets them through existing lifecycle ownership.
- Formatter matrix: `dp`, step, trailing digits, no grouping, all six spaced percent languages plus an unspaced language, degree unspaced, prime spaced, monetary, duration, numeric device classes, date/time/timestamp, invalid parse/raw fallback, exact raw translation-dependent states, the four literal labels, friendly/object ID, and locale/server/local timezone resolution.
- Icon/state-color matrix: override state-aware cases, live domains, battery thresholds, unavailable, row/registry/state precedence, MDI/custom/unknown fallback, injected missing SF symbols and final nonblank text fallback.
- Header intent covers absent/empty/nonempty title, explicit flags, two configured-but-missing rows, actual candidates, `some on` checked value and exact safe targets. Prove caller/action gate precedes optimism, optimistic state retains attributes/context/timestamps, no local rollback timer exists, and cancelled/late completion cannot mutate state/lifecycle/error.
- Secondary tests prove position/tilt zero visible, brightness zero absent, positive brightness rounded visible/accessibility values, and missing `last-triggered` exact label/value. Actions test absent, more-info, none and every unsupported preserved action.
- Integration injects entity snapshots only: burst update changes the intended presentations; duplicate rows remain two; disappear/stop/reconnect leaves no formatter task/observer and rejects late service result under C05 gates.

### GUI/manual/accessibility

Run `@MainActor` hosted AppKit captures at 496 and 320 points, dark Aqua, 2x, fixed `en_US_POSIX` and explicit UTC/Asia-Shanghai metadata. Write PNGs for numeric/unit, unknown, unavailable, missing, on/off/disabled switch, long name, entity-id/secondary, duplicate rows, and mixed domains. Assert PNG signature/dimensions/nonblank/semantic regions plus row height/truncation/ divider/color-role/toggle state; manually compare equivalent hass frontend states before approving any OS-labelled baseline.

Verify accessibility labels/values, source order, primary-row then toggle focus, Space activation, no `tap_action:none` primary target, and disabled missing/ unavailable controls. Assert the exact position/tilt/brightness label/value pairs and icon-warning/fallback semantic labels. No custom animation is planned; stable system-control states are the oracle and reduced-motion is N/A.

### Performance, release, and live read-only

Measure pure cold/warm presentation for 500 mixed rows and 100-of-500 state updates outside bitmap capture using XCTest clock/CPU/memory stored baselines. Repeat card create/remove and dashboard stop/reconnect cycles; no retained observer/task/service handle may remain. Build release on a macOS 12 runner, prove every preferred SF symbol resolves or takes the nonblank fallback, and run full inherited suites. The live smoke may read state/config/registry/locale/Lovelace and compare the 66 row shape and representative states, but must not invoke a service, toggle, navigate persistently, or change HA state. Scan artifacts for tokens and inspect exact allowed diff. Migration evidence is explicitly N/A: the module adds no persistence/config/bootstrap schema and must not rewrite raw Lovelace; any discovered need for migration is a stop-and-research result.

## Risks and stop rules

- Stop if the live frontend language changes from `en`, or a proposal requires dynamic MDI/catalog resources, translations, area/device registry data, a new `AppConfig` policy, profile/settings work, a service retry/transport change, or a policy decision outside D06-01..07.
- Stop if a source duplicate would be collapsed/re-keyed, a synthetic row takes source identity, Module 04 raw data changes, or any Module 05/12 owner tail is bypassed.
- Stop if an unavailable/missing/late/stopped control can issue a service or optimistically publish state, if optimism occurs before `canInvoke`, if a service completion rewrites entity state, or if a header gains an aggregate owner/task.
- Stop rather than implementing weather/climate/fan specialized rows, full action types, graphs/history/range, or dynamic icon/translation parity.

## Handoff

Verdict: **complete / independently verified**, contract revision 2. C06-01 through C06-11 are green, no material product/bootstrap/migration/behavior question remains, and the implementation contains no new owner, fetch, subscription, cache, persistence key, or `AppConfig` surface. The regenerated Module 06 graph is green at 138 nodes / 935 edges / three cycles / zero unresolved / not truncated, fingerprint `fdcbec4441919ce38e9783ce10203a69b98c5de5afd2a6f6dd5a19e3cde1fed3`. The resolver self-test passes at 31 nodes / 61 edges, fingerprint `26a89dfc1a88704dcb44a2fc97d2c5c41f20bacf0eb79f5816f20ecfb26e9372`.

The exact next staged action is **Module 08 research only**. Preserve the fixed single-server bootstrap, Module 04 raw/resolved identity, Module 05 lifecycle and service tail, Module 06 row presentation boundary, verified Module 07 current conditions with forecast still deferred, Module 12 navigation ownership, Core Graphics primary rendering, and the open Module 09 stale- viewport fallback. Do not begin Module 08 implementation, broader Module 09, or Modules 10/11 until a bounded green Module 08 evidence packet has been researched and independently audited.

## Change log

- 2026-08-31: Initial revision 1 research packet, manifest, and green graph.
- 2026-08-31: Independent-audit correction added exact row/icon/color/power/action/focus matrices, full hashes, bootstrap/specialized boundaries, and regenerated graph anchors; no user decision remained under the existing staged Module 06 plan.
- 2026-08-31: Fresh-verifier correction added already-fetched registry `ic`, inherited optimistic-service ownership, self-contained structured names, exact literal/state/unit/secondary/header rules, and the macOS 12 SF-symbol availability gate.
- 2026-09-01, contract revision 2: corrected the pinned implicit row-factory matrix so `group`, `humidifier`, `valve`, and every other reference-specialized implicit domain are visible unsupported; only nine toggle domains plus `sensor`/unmapped simple remain generic, while literal climate/weather remain deferred. Fresh independent re-verification also proved bidirectional same-entity exclusion across row-domain and header-`homeassistant` power routes. Focused 27/27, full 260 plus three skips, macOS-12 release/symbol, GUI/accessibility, performance, lifecycle, read-only live, context, and resolver gates passed. Status advanced to `complete`; Module 07 research only is next.
- 2026-09-08, contract revision 2 unchanged: inspected the Module 07 shared model/presentation anchors and regenerated a green 138-node / 935-edge graph. The specialized weather card does not change generic row contracts; Module 07 forecast remains deferred and Module 08 research only is next.
