---
schema: nativeha-evidence/v1
module: "08"
title: Native Markdown and server template lifecycle — stage 1
plan: ../../rescue-plan/module-08-markdown-card.md
status: complete
contract_revision: 1
depends_on: ["02", "04", "05", "12"]
reference_revision: dbc68cc5c59ce720a47e5f4aa3d9d7a68d84fdbd
nativeha_revision: e43010778fe1d5a06b777580fc6ccd7b60a72fac
graph_file: ../generated/module-08.dependencies.json
graph_fingerprint: ebb0c5d91564dad1cf52bc455ed2920b9bae310205e5a01728e6cc6773379b61
last_validated: 2026-09-12
---

# Module 08 evidence packet

## Scope delta

The user approved staging native Markdown and HA templates first, with an explicit fallback for advanced HTML, media and HA-specific custom elements. This is scoped completion, not full web-renderer parity. See [approved intent](../../user-deviations.md#markdown-implementation-stages). No JavaScript/WebView runtime, local Jinja evaluation, editor, profile store, graph redesign or automatic promotion of maintenance-view cards into Home.

The read-only 2026-09-12 deployment check found two identical Markdown cards, both in excluded maintenance views `home_3h` and `home_12h`; Home/default_view contains none. Default Home therefore creates zero Markdown owners today. Use equivalent fixtures and explicit direct routing for validation.

Correct historical plan assumptions: mounting determines subscription demand. The ordinary hui-card wrapper removes an empty self-hidden Markdown element, which disconnects its subscription; a standalone element has different behavior. The reference renders all source strings through HA, including strings without Jinja markers. Empty source configuration differs from an empty successful result. Module 04 already preserves raw config/options. The current-user decode now retains the optional name from the existing `auth/current_user` response alongside identity; no second request is added.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| C08-01 | Decode Markdown configuration | Require nonempty source content; whitespace is valid. Preserve raw unknown keys, title, text_only, show_empty, card_size and actions. Runtime `entity_id` accepts string or array and maps to wire `entity_ids`; plural config alone is not the runtime selector. | Correct only researched decoder gaps; preserve exact resolved identity. | HuiMarkdownCard.setConfig; subscribeRenderTemplate | LovelaceCard typed accessors | Empty/string/array/unknown/raw round-trip fixtures |
| C08-02 | Mounted supported card with authenticated client | Subscribe using `render_template`, source, singular-config entity IDs, variables `{config: full raw config, user: current user name}`, strict true, report_errors false outside preview. Marker-free source also subscribes. | One owner per actually rendered supported resolved card; unsupported container descendants and extra panel cards create no owner; no per-state-update resubscription or local template interpolation. Do not substitute ID or a fabricated name. Missing name blocks only this card subscription, preserves any prior result and presents a metadata-unavailable state; successful ordinary bootstrap retry supplies the name and resumes demand without an extra fetch. | HuiMarkdownCard._tryConnect; ws-templates | Typed core template API; dashboard Markdown coordinator | Exact wire payload and duplicate-card isolation |
| C08-03 | First result, content edit, reconnect | Initial uncached body is blank. Retain previous result while the same component reconnects or changes content in place; a newly created config component starts from the complete-config cache or blank. | An actually changed installed dashboard raw config invalidates all cached views and creates new wrappers, even where a view/card config is equal. Use a configuration/view incarnation alongside exact card identity; changes retire/remount owners and retain values only through the 1s config cache. Entity updates, graph-range changes and same-config reconciliation do not remount. Only an in-place setConfig on a surviving component preserves its request for same-content edits; editor/preview is outside this stage. An unchanged surviving owner and transport reconnect preserve the original request. Retired callbacks cannot publish. | setConfig; _tryConnect; Connection.subscribeMessage | Markdown owner state and generation | Pending first ACK/event, in-place config versus actual reload/remount, reconnect, ABA |
| C08-04 | Result/error events and subscription rejection | Success stores result/listeners; stream errors retain latest error or warning unless ERROR already dominates. A later success does not clear that alert. Rejection falls back to source; rejection alert is preview-only. | Stream error does not overwrite previous successful body. Cancellation is quiet. A new card connection attempt clears alert; card disconnect clears it only if a pending/installed handle exists; physical transport reconnect retains it; avoid retry loops on rejected subscribe. Listener metadata does not cause client-side filtering. | _tryConnect/_tryDisconnect | Template event enum and presentation | ERROR→WARNING→success, warning→ERROR, rejection, cancellation |
| C08-05 | show_empty false and successful result | Hide only a present result whose string length is zero; whitespace is not empty. text_only hides header/card chrome and uses compact padding. | Ordinary hui-card sees the child hidden flag, removes it and cancels its subscription. Keep a hidden retained state without automatic resubscribe; cached parent-view return leaves the detached child hidden. Only child recreation/config replacement can reconnect, subject to a cached empty result. Standalone-component empty→nonempty behavior is not the dashboard oracle. Parent layout releases hidden-card spacing. | updated/render/styles | MarkdownCard and dashboard layout | Empty→hidden/cancel without auto-retry; remount; pending/whitespace; title/text-only artifacts |
| C08-06 | Card/view/config/app retirement | Cancel pending or installed subscriptions and rendering; reject late callbacks. Distinct card identities never share mutable result state. | Use existing weak app lifetime and serialized owner operations, including detached-operation and emergency-deinit ownership inventories before async cleanup. Offscreen viewport position alone does not retire an owner; actual wrapper hiding/removal does. | disconnectedCallback; Module02/05/12 ownership | Dashboard Markdown coordinator and owner reconciliation | Held ACK/remove, view switch, stop/retry, deinit, reconnect, owner-zero |
| C08-07 | Disconnect and rapid remount | Reuse last result by complete config key within reference's 1000 ms cache lifetime, without bypassing a new connection attempt: a newly created component starts connecting before cache-driven empty hiding retires it; this differs from returning to an already hidden cached component. | Cached HUIView reattachment retains its component result beyond 1s and resubscribes. Keep immutable per-card result across view absence within the same config incarnation, distinct from the 1s new-component cache. An empty self-detached child remains hidden across cached-view return. Any changed installed dashboard raw config retires all retained-view states; returning to a surviving cached component reparses its accepted result if previous background preparation was canceled. Config object key order irrelevant, array order significant. Reference timers expire on each set; do not reinterpret 1000 as entry capacity. Never mix mutable subscription identities with cached immutable output. | CacheManager; object-hash; willUpdate/disconnectedCallback | Template result cache | Fake-clock miss/hit/expiry/config-key/repeated-set; same-instance view return after >1s; config replacement |
| C08-08 | Markdown string after server result/fallback | Native layout for headings, paragraphs, emphasis/strong/strike, links, ordered/unordered lists, inline/fenced code, line breaks, blockquotes, native GitHub alert callouts (NOTE/IMPORTANT→info, TIP→success, WARNING→warning, CAUTION→error), rules and GFM tables/task lists. Normal Markdown single newlines break. Literal math remains literal; no syntax-highlighting requirement. | Parse/prepare off-main, publish only current revision; preserve reference content and accessibility without running JS. Apple parser's presentation intents require native block layout. GitHub alerts follow the DOM converter: a case-insensitive marker anywhere in the first child text triggers conversion even if escaped or code-formatted, and every flattened child matching that entire first text chunk is removed (same-line plain text may disappear). The breaks-enabled path flattens paragraph containers and removes empty-text children such as br; separately formatted child content survives. | ha-markdown-element; markdown-worker; marked/xss | Markdown parser/document/renderer | Semantic tree fixtures, narrow/normal renders, reference outputs |
| C08-09 | Deferred HTML/media/custom element syntax | Show explicit unsupported-content notice and selectable literal source for the affected document; no silent stripping or resource fetch. | This stage's fallback is user-approved; generic full web HTML/media/custom-element support remains deferred. Retain full output, including template-rendered deferred syntax. | User staging decision; worker allowlist | Markdown parser/fallback presentation | HTML/image/audio/video/custom tag and mixed-content fixtures |
| C08-10 | Markdown links | Classify destinations before dispatch; external destinations use native system handling, supported same-server Lovelace routes use Module12 routing. Preserve text even if destination cannot activate. | Unsafe/unhandled destinations receive explicit inert fallback. No browser/network side effect in tests. On an interactive card the configured card action consumes link activation, matching the reference; passive-card links navigate. | ha-markdown-element link postprocessing; navigation helpers | Link policy and existing navigation boundary | Relative/absolute/internal/external/unsafe links; keyboard activation |
| C08-11 | Configured card actions | Passive cards have no button role; explicit actions determine interactivity. Support none, navigate to a resolvable existing Lovelace view, more-info for an explicit entity, and safe external URL actions. Other actions (including service/toggle/assist/fire-dom-event and confirmation-bearing actions) show an explicit unsupported-action notice and execute nothing; full generic action parity remains outside this stage under the original plan. | No service/state-changing live test. Hold/double action resolution and keyboard activation must preserve supported actions; an unsupported configured action must never execute a different fallback action. | _interactive; hasAction; actionHandler; handleAction | Existing action dispatch or bounded adapter | Tap/hold/double/link isolation/accessibility fixtures |
| C08-12 | Repeated results and large documents | Prepare asynchronously; latest-current generation alone publishes. Keep updates isolated to the affected card and cancel retired work. | Debug-only diagnostics; release has no logging overhead. Cache policy must not become a silent payload-size truncation or leaked owner. | Approved native/performance/logging contracts | Document preparation and coordinator | Cold/warm 1 MB, 100-card isolated updates, churn and memory/owner tests |

## Source anchors

Reference revision is pinned above; `nativeha_revision` is the research base. Native hashes in the graph describe the tested implementation. Runtime packages: marked 18.0.5, xss 1.0.15, object-hash 3.0.0, Comlink 4.4.2 and home-assistant-js-websocket 9.6.0. Package/lock identities are in the [generated graph](../generated/module-08.dependencies.json).

| Reference path | Symbols | SHA-256 |
|---|---|---|
| `src/panels/lovelace/cards/hui-markdown-card.ts` | HuiMarkdownCard | `f50a78a58e08ad26311fb23034e1726d89933c62f6ebea1d9cee142d35440efd` |
| `src/components/ha-markdown.ts` | HaMarkdown | `fbe676bf4ba9d274285b33156f76275733b276921b7f85a2a25728aed3ecfc82` |
| `src/components/ha-markdown-element.ts` | HaMarkdownElement | `8947da2643b21ec0b1127cbb3dfa7bfcb2b622e8b9d77577d03643b2b2eb8bc8` |
| `src/resources/render-markdown.ts` | renderMarkdown | `852c4b85c4efb63913c5f7acac48275d39ee70fcbadfa3729ae473a25b18a527` |
| `src/resources/markdown-worker.ts` | module runtime | `ff53bfeaba14e2788cfbb2c5f978ebd9c87feb010df4e2d21c7625463f98b717` |
| `src/data/ws-templates.ts` | subscribeRenderTemplate, RenderTemplateResult, RenderTemplateError | `4e0e400bdde40117f4f1f03b4a0e975beb5b8fc13c6d736d141efd7f7f82bfe7` |
| `src/util/cache-manager.ts` | CacheManager | `2e542acdbf31ee5cc45d842ddce35d44a731fded930ce3833f4e5e21ac6cfccb` |
| `src/panels/lovelace/common/has-action.ts` | hasAction | `fdae56ecfe56a485528bbc75882f002b4afe3a455bb13eeef19423f9bc211466` |
| `src/panels/lovelace/common/handle-action.ts` | handleAction | `f0276cbaa278333684e31cfb56a27b37fe578ace18bebf576d7cab938c82fdfc` |
| `src/panels/lovelace/common/directives/action-handler-directive.ts` | actionHandler | `ef9f129d36010fab3037fdf1906018d29bc4c601125b5c892d7d0252507cfa5d` |
| `src/common/dom/is-navigation-click.ts` | isNavigationClick | `87d6130b4c6d2a0e141c1666624ec5fec093a4f87f66d788dad471e83090445e` |
| `src/common/navigate.ts` | navigate | `6ca2c178560d9e48bd02d3a861fdc28b98a66dc1cc9f519db55e059a35809e4d` |
| `node_modules/home-assistant-js-websocket/dist/connection.js` | Connection | `884929a38078cc51cb47b0d7d8a821ef99bc784bcd50792bf9b044f936db69e8` |
| `node_modules/home-assistant-js-websocket/dist/messages.js` | module runtime | `5de87c3bf01207c73424e51a0676705afee7afc2efde7cb8707dfafe709a7b35` |
| `node_modules/object-hash/dist/object_hash.js` | module runtime | `3bb38b9ae6002158700d776f34a2ebd2225f1bb1f41d9e91e286d69cf85bec98` |
| `node_modules/marked/lib/marked.esm.js` | module runtime | `43e1fc0927b2d397bdc786c0a9efa8414ce18e7781d0b3490faceea35b7d0d15` |
| `node_modules/xss/lib/index.js` | module runtime | `6b7c5aa2176162838421e891a60c8c4b4205fa292a5a7bda51f27075be2b7b1b` |
| `node_modules/xss/lib/default.js` | module runtime | `b31eddcf7ba7983be68a756e9c94b0eafdde42a3ade4feb3f91d9d5687f986f2` |
| `node_modules/xss/lib/parser.js` | module runtime | `e01de1d37f0d450bc29d636bc95bf4274741520e490f8e6ff9b238c31d0a1f39` |
| `node_modules/xss/lib/xss.js` | module runtime | `e727dd7dc506cc3c5eddba78b1688351df42c11c5bd9f8d365f6b9928d97646c` |
| `node_modules/comlink/dist/esm/comlink.mjs` | module runtime | `ba9d0de49a44aa9f42c70d6e98e2f00ef3836ca11b785dccd707917d6a4c719b` |
| `src/panels/lovelace/cards/hui-card.ts` | HuiCard | `13e2df041421c89ef55e4b9141f3f7e171db7d94ea66620064df9819e431d626` |
| `src/panels/lovelace/cards/hui-stack-card.ts` | HuiStackCard | `09f9c24a979bfa5127b7e60c8f2cafeed9d6b608f9a3005cabd3197b08aeb831` |
| `src/panels/lovelace/cards/hui-vertical-stack-card.ts` | module runtime | `1ee5141d652bf5bf39e025be90b068f0f13f90979d33fcf7820e092e983912cd` |
| `src/panels/lovelace/views/hui-view.ts` | HuiView | `7050ef76d0955302bbe041ed1bdfab8f5602ce8a9448c36bddf29ceb2285c9f3` |
| `src/data/ws-user.ts` | userCollection, subscribeUser | `a37a7d50007c6219031be9e2dfec38db09ae3f82a2d375a25794c310eecd702a` |
| `src/state/auth-mixin.ts` | module runtime | `f3c18c5cc772d196776be86fb0c6920df939d65a59ca5f6b4462ef760f7b2806` |
| `src/panels/lovelace/hui-root.ts` | HUIRoot | `b0d88e019b04e28fa51e18feea92120ef772a4090b92dba7b326c149884a8a9d` |
| `src/panels/lovelace/create-element/create-card-element.ts` | tryCreateCardElement | `4a9cf4b8624c1bbb85ede2f84b9c5fe5b56a7bf364320f13ede116cbf279b5be` |
| `src/panels/lovelace/create-element/create-element-base.ts` | createErrorCardElement | `9b4f30ba3135ee3298369b845f4c13904d92eb5c0d02a60126f59865af7d6fe8` |
| `node_modules/xss/lib/util.js` | module runtime | `6f0baafbd1634f644267941fb37240604d1e5b8ce7c05ebc25f687330206f880` |
| `node_modules/object-hash/index.js` | module runtime | `99af0590e6993552b8a3313cb40843cfa9ad5be62abd966340d394a2f732178d` |
| `node_modules/home-assistant-js-websocket/dist/collection.js` | module runtime | `e558c8bc30820acd693807d4f96a3a5b8b09f415147038ca1464df8a1c2f3ce8` |
| `node_modules/home-assistant-js-websocket/dist/store.js` | module runtime | `37d153b62fef698c78fb35bdd7dc26014fccf9169942124d770394c0c0b739a4` |
| `node_modules/home-assistant-js-websocket/dist/commands.js` | module runtime | `88685ebfab7320de32a6db9dcd77fa7228dc23905b5a77bc3c38bee6b10123bd` |
| `src/components/ha-alert.ts` | module runtime | `709566dca93a9657fef4e42e3a03578ef2db830afdc88ea7cf4b306ef90a41cb` |
| `src/components/ha-card.ts` | module runtime | `e7c941041f4e2ae2fe402648fff2587e3781dbd1f26fb711c8db1f6f77cb142b` |

## Dependency traces and boundaries

Discovery follows one import level from explicit reviewed seeds to avoid indexing unrelated editor/assist subsystems. This is not a behavioral stop: wrapper/view/root creation, worker, parser, sanitizer, hashing, cache and subscription runtime implementations are explicit seeds, including hidden Worker/Comlink and browser-package redirects. Review follows relevant source until platform/API or documented deferred boundaries regardless of graph depth.

- `HuiMarkdownCard` → `subscribeRenderTemplate` → browser Connection runtime: subscribe/ACK/event/cancel/reconnect, reusing verified Module02 contracts.
- Card → CacheManager and object-hash runtime: one-second expiry and complete configuration value key semantics; digest algorithm itself is replaceable by an equivalent native structural key.
- `ha-markdown` → `ha-markdown-element` → renderMarkdown → explicit worker runtime seed → marked lexer/parser → xss whitelist/parser and CSS filter. The worker is reached through Comlink and a Worker URL; a type edge alone does not discover it. Native implementation stops at equivalent parsed document/explicit deferred fallback, not DOM or JavaScript execution.
- The graph currently reports two reviewed nonliteral/unresolved boundaries: Node `crypto` from object-hash (digest primitive; browser bundle explicitly seeded) and the allowlisted dynamic custom-element import (ha-icon, ha-svg-icon, ha-qr-code deferred; ha-alert generated callouts mapped natively in stage 1). Record checker yellow honestly; these are not stale sources or unexamined template/Markdown dependencies. CSS filter is irrelevant because the normal sanitizer permits no style attributes.
- Custom-element dynamic imports and media/layout DOM behavior are inventoried as deferred stage boundaries under the user's decision. Full supported syntax must be identified before classifying unsupported input.
- Independent research review covered card actions and internal navigation; implementation verification must still exercise their native adapters.

## Native mapping

| Contract | Existing/planned Swift path | Ownership/state | Notes |
|---|---|---|---|
| C08-01/02 | LovelaceModels.swift, Models.swift, HomeAssistantTemplate.swift | Existing raw config and current-user bootstrap; typed template event | Add name without another bootstrap command |
| C08-03–07 | DashboardMarkdownCoordinator.swift; DashboardViewModel.swift | Resolved-card owner map, weak lifetime, request generation, immutable result cache | Reuse owner reconciliation and transport; no observer per entity |
| C08-08–10/12 | MarkdownRendering.swift, MarkdownCardView.swift | Value document, background preparation, native block layout | Keep CardViews dispatch small |
| C08-11 | Existing entity/navigation boundary plus typed Markdown action classifier | none/navigate/more-info/url; explicit non-executing notice for others or confirmation | No state-changing live calls |

## Decisions and native deviations

| ID | Decision | Reason | Preserved semantics | Verification | Status |
|---|---|---|---|---|---|
| D08-01 | Stage advanced HTML/media/custom elements with explicit literal fallback | User-approved stage | Complete text preserved; no false parity claim | C08-09 | approved 2026-09-12 |
| D08-02 | Native structured layout from parsed Markdown | Native platform | Block/inline meaning, breaks, links and readable layout | C08-08 | implemented; fixture and scoped visual verification |
| D08-03 | Generation-aware ownership and background parsing | Native concurrency | Retired result suppression and responsive input | C08-03/06/12 | required |
| D08-04 | Retire cached-empty pending startup immediately through native cancellation | Existing approved native transport cancellation/generation contract | Reference disconnect clears logical ownership immediately; native callbacks cannot revive a retired card | C08-05/06/07 | native transport adaptation |

For a newly created component seeded with an empty cached result, reference `_tryDisconnect` clears its logical handle and alerts synchronously, then waits for the pending promise only to unsubscribe the wire handle. NativeHA uses the already-approved transport cancellation boundary to retire pending startup immediately after the connection attempt. It does not wait for ACK while keeping an active card owner, nor allow a rejection of a canceled attempt to revive that hidden card. This is an explicit native scheduling/cancellation adaptation, not a claim that Swift reproduces browser promise timing. The existing [native transport decision](../../user-deviations.md#native-websocket-transport-semantics) and C08-03/06 retired-callback suppression govern this case.

## Validation

### Offline deterministic tests

Final implementation validation on macOS 12.6.7 / Swift 5.6.1:

| Check | Result |
|---|---|
| Focused parser/lifecycle/rendering/interaction suites | 23 passed |
| `swift test` | 356 tests, 5 skipped, 0 failures; 120.405 s |
| `swift test -c release` | 344 tests, 5 skipped, 0 failures; 82.034 s |
| Release logging non-evaluation regression | Passed |
| Exact worker oracle | 24 cases passed |
| Exact alert DOM-conversion oracle | 17 cases passed |

The five skips in each full suite are opt-in graph benchmarks and live history/weather smoke tests. They are not Markdown failures or passing live coverage. The separate read-only template smoke is recorded below. Deferred graph/climate/axis work is not closed by these runs.

Tests in `MarkdownTests.swift` and `MarkdownLifecycleTests.swift` cover exact payload/config/name handling, duplicate-card and 100-card isolation, error precedence, reconnect request retention, retained views versus config replacement, repeated cache deadlines, empty-wrapper retirement, held ACK and deinit, supported-container demand, native keyboard/tap/hold/double action handling and link consumption. Parser regressions cover the worker corpus and all alert cases, empty tables, escaped tasks/link destinations, list/quote identity, and literal code inside variable-length, list and quoted fences. The reference oracles establish web output separately from native conformance; source hashes and nonblank captures alone are not semantic tests.

### Read-only live smoke

The read-only probe fetched config/current user and subscribed to both existing Markdown source strings. Both succeeded with identical plain-Markdown output and four entity listeners. No services, config mutation or state changes. Exact config/result evidence is preserved in `Tests/Fixtures/Markdown/live-template-capture.json`. The refreshed 09:21 UTC capture used the actual current-user name, complete raw config, `strict:true` and `report_errors:false`. Both subscription and unsubscribe acknowledgments succeeded. The tracked Node probe establishes HA acceptance of the intended request shape; Swift wire tests establish what the production client actually sends.

### Visual and animation oracle

Sixteen native production-view captures and matching 496/320-point reference fixtures were inspected independently. Shared `tools/markdown-reference/core.md` and `status.md` prevent parser-boundary differences between composites. Native artifacts are reproducible in `.build/render-artifacts/markdown-*.png`; captures cover core syntax, status, status-text-only, live text-only, pending with title, retained error, live result and the explicit native fallback.

The scoped content/layout gate passed: complete visible content, no clipping, corrected headings/lists, continuous quote decoration, intrinsic table sizing, alert body/icon sizing and title/text-only/error presentation. Hidden-card removal and actions are semantic tests, not fabricated blank images or claims based on screenshots.

Reference captures use `tools/markdown-reference/visual-harness.mjs --capture` with exact worker output, extracted CSS/fonts, static shadow DOM and researched alert mapping. They are component-style approximations, not the full live HA runtime. The Browser skill reported no available browser connection, so isolated headless Chrome generated the offline captures with network requests blocked. Custom live themes, full runtime interaction and event-to-frame timing were not verified. Native font/glyph rasterization differs from the browser. No current native output or approximation was approved as a golden; no decorative animation was added.

### Performance and lifecycle

Cold/warm preparation and 100-card isolation measurements are recorded with methodology and platform limits in [Benchmarks/Markdown](../../../Benchmarks/Markdown/results.md). Release cold parsing of the 1,048,598-byte fixture averaged 2.379 s off the production main-actor path; 100 updates among 100 cards settled in 8.30 ms with zero dashboard-wide publications. The 64 MiB diagnostic cache's warm result is explicitly separate from the default 16 MiB cache, which fully renders but does not retain the oversized dense fixture. Cache cost accounting is estimated, not a process RSS ceiling; noisy/zero XCTest memory metrics are not presented as allocation proof. Owner snapshots and cancellation/deinit tests check retirement independently of those metrics.

Stream errors and parsing failures use the existing debug-only `AppLog` path; subscription rejection diagnostics come from the core transport. No eager logging metadata, routine result logging or release logging storage was added.

## Open questions and risks

- Ordinary dashboard reload and stack setConfig create fresh hui-card wrappers. Keep existing exact native identity; do not invent source-path owner transfer to imitate a component-level in-place update absent from this app stage.
- Foundation Markdown differs from marked/xss. Establish fixture oracles and handle unsupported constructs explicitly instead of assuming parity. The separate GitHub-alert DOM conversion has observable quirks: escaped/code markers still trigger conversion, and filtering removes the first text chunk containing the marker, not just the marker substring. With breaks enabled, paragraph wrappers and empty-text br children are removed, so separate lines and paragraphs can become adjacent text. The separate alert oracle records these DOM results instead of assuming ordinary blockquote semantics.
- Default Home has no Markdown cards, so live smoke alone cannot prove native mounting/layout behavior; fixtures and direct route are required.

## Independent verification and handoff

GO for scoped stage 1. The independent verifier ran 23 focused tests (21 parser/lifecycle/rendering and 2 native interaction), all passing, and reviewed the full debug/release logs including release logging non-evaluation. Contract results: C08-01/02 decode/wire; C08-03–07 ownership/cache/errors/reconnect; C08-08/09 native syntax/fallback; C08-10/11 links/actions/accessibility; and C08-12 publication isolation/cancellation all pass in the reviewed scope. Performance, read-only live smoke and scoped visual comparison were performed separately as recorded above; the verifier did not claim to repeat them. No known medium-or-higher blocker remains in this stage.

Resolver self-test and both reference oracles pass. All eight other affected graphs are refreshed and green. Module 08 has fresh anchors and exactly the two reviewed dependency boundaries described above; strict checking exits yellow for those boundaries, not stale or missing behavior evidence.

Preserve these contracts in later modules. Advanced HTML/media/custom elements, full generic actions, live-theme visual fidelity and browser-level navigation remain outside this staged completion. Next bounded plan work is Module 10 climate-detail research; keep the dedicated graph redesign and previously deferred findings under their existing user-directed scope.

## Change log

- 2026-09-12: staged research, native implementation, parser/lifecycle fixes, full debug/release validation and independent scoped verification completed.
