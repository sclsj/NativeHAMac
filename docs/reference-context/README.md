# NativeHA reference-context index

This directory is the durable handoff between read-heavy reference research and Swift implementation. The rescue plans define scope and intended architecture; the files here record revision-pinned evidence, current contract status, and the exact next action.

Do not copy generated dependency graphs into prompts or evidence packets. Run the staleness check, then read only the packet and the graph nodes named by the packet.

| Module | Rescue plan | Evidence packet | Status | Contract revision / prerequisite | Next action |
|---|---|---|---|---|---|
| 02 | [WebSocket multiplexer](../rescue-plan/module-02-websocket-multiplexer.md) | [Module 02 evidence](modules/module-02-websocket-multiplexer.md) | complete; post-Module 07 anchor refresh green | 2 | Preserve verified transport/lifecycle contracts in later modules |
| 01 | [History stream](../rescue-plan/module-01-history-ws-stream.md) | [Module 01 evidence](modules/module-01-history-ws-stream.md) | complete; post-Module 07 anchor refresh green | 3 / Module 02 complete | Preserve resolved history identity, unified owner operations, feed/render lifecycle, and the separate Module 09 fallback in later modules |
| 04 | [Lovelace decode](../rescue-plan/module-04-lovelace-model-decode.md) | [Module 04 evidence](modules/module-04-lovelace-model-decode.md) | complete; post-Module 07 anchor refresh green | 1 / Fresh complete 02 and 01 handoffs | Preserve exact resolved identity and unified owner lifecycle in later modules |
| 03 | [Profile isolation](../rescue-plan/module-03-appconfig-profile-isolation.md) | not created | intentionally skipped; not complete | N/A / fixed personal deployment deviation | Preserve the existing server/token bootstrap; no profile switching or settings UI |
| 12 | [Sidebar and views](../rescue-plan/module-12-sidebar-lovelace-views.md) | [Module 12 evidence](modules/module-12-sidebar-lovelace-views.md) | complete; post-Module 07 anchor refresh green | 1 / Requires 04; preserves 01 and 02 | Preserve exact view/card identity and unified ownership in later modules |
| 05 | [Dashboard state](../rescue-plan/module-05-dashboard-viewmodel-state.md) | [Module 05 evidence](modules/module-05-dashboard-viewmodel-state.md) | complete; independent verification and post-Module 07 graph green | 1 / Complete 01, 02, 04, and independently verified 12 | Preserve lifecycle/entity/service ownership in later modules |
| 06 | [Entity display](../rescue-plan/module-06-entities-state-display.md) | [Module 06 evidence](modules/module-06-entities-state-display.md) | complete; independently verified; post-Module 07 graph green | 2 / Complete 04 and 05 | Preserve exact row presentation, duplicate identity, static safe power routing, and accepted-generation `ic` carry |
| 07 | [Weather](../rescue-plan/module-07-weather-card.md) | [Module 07 evidence](modules/module-07-weather-card.md) | complete; revisions 1 and 2 independently verified | 2 / Complete 02, 04, 05, 06, and 12 | Preserve current-card and modal weather-detail contracts; keep C07-09/10 dashboard forecast deferred |
| 08 | [Markdown](../rescue-plan/module-08-markdown-card.md) | not created | unresearched; next research gate | Requires 02 and 04; Module 07 revision 2 complete | Research Module 08 only and correct the stale assumption that template-subscription demand can be inferred solely from content markers; do not implement until research and audit are green |
| 09 | [Graph rendering](../rescue-plan/module-09-graph-rendering.md) | [Module 09 bounded async-repair evidence](modules/module-09-graph-rendering.md) | bounded async repair verified; post-Module 07 graph green; stale-viewport fallback open; broader module unresearched | 3 / Module 01 implementation complete | Keep the correctness-safe fallback; later repair stale visual inputs with coordinator-owned provenance, not hash/timestamp ordering |
| 10 | [Climate detail](../rescue-plan/module-10-climate-detail.md) | not created | unresearched | Requires 05 and 06; fixed-server assumption replaces 03 | Card/detail phase |
| 11 | [Fan detail](../rescue-plan/module-11-fan-detail.md) | not created | unresearched | Requires 05 and 06 | Card/detail phase |

## Files

- [`module-workflow.md`](module-workflow.md): researcher, implementer, and verifier responsibilities plus copyable prompts.
- [`evidence-packet-template.md`](evidence-packet-template.md): canonical human packet structure for later modules.
- [`manifests/`](manifests/): reviewed TypeScript/runtime seeds and traversal boundaries.
- [`generated/`](generated/): deterministic dependency graphs. These are rebuildable candidate-discovery artifacts, not behavioral conclusions.
- Root `AGENTS.md`: concise phase routing and maintenance rules for this richer workflow. Keep operational detail here rather than expanding root context.

## Module 02 commands

```sh
node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-02.dependencies.json

node tools/reference-context/trace-ts-deps.mjs \
  --manifest docs/reference-context/manifests/module-02.inputs.json \
  --out-json docs/reference-context/generated/module-02.dependencies.json \
  --out-markdown docs/reference-context/generated/module-02.dependencies.md

node tools/reference-context/test-resolver.mjs
```

Run the checker first. Rebuild only on yellow/red or after deliberately changing the manifest/resolver. A moved reference `HEAD` alone does not invalidate the packet; anchored content hashes decide whether targeted research is required.
