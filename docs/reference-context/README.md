# NativeHA reference-context index

This directory is the durable handoff between read-heavy reference research and
Swift implementation. The rescue plans define scope and intended architecture;
the files here record revision-pinned evidence, current contract status, and the
exact next action.

Do not copy generated dependency graphs into prompts or evidence packets. Run
the staleness check, then read only the packet and the graph nodes named by the
packet.

| Module | Rescue plan | Evidence packet | Status | Contract revision / prerequisite | Next action |
|---|---|---|---|---|---|
| 02 | [WebSocket multiplexer](../rescue-plan/module-02-websocket-multiplexer.md) | [Module 02 evidence](modules/module-02-websocket-multiplexer.md) | complete | 1 | Use the verified multiplexer contract in Module 01 |
| 01 | [History stream](../rescue-plan/module-01-history-ws-stream.md) | not created | unresearched | Module 02 complete | Dispatch Module 01 researcher |
| 04 | [Lovelace decode](../rescue-plan/module-04-lovelace-model-decode.md) | not created | unresearched | Depends on 02 for fetch path | Dispatch researcher after 01 |
| 03 | [Profile isolation](../rescue-plan/module-03-appconfig-profile-isolation.md) | not created | unresearched | Independent, but ordered after 04 in the rescue plan | Dispatch researcher after 04 |
| 12 | [Sidebar and views](../rescue-plan/module-12-sidebar-lovelace-views.md) | not created | unresearched | Requires 04; coordinates with 01 | Dispatch researcher after 03 |
| 05 | [Dashboard state](../rescue-plan/module-05-dashboard-viewmodel-state.md) | not created | unresearched | Requires 01, 02, 03, 04, and 12 | Dispatch when prerequisites are verification-ready |
| 06 | [Entity display](../rescue-plan/module-06-entities-state-display.md) | not created | unresearched | Requires 04 and 05 | Card/detail phase |
| 07 | [Weather](../rescue-plan/module-07-weather-card.md) | not created | unresearched | Requires 02, 04, and 05 | Card/detail phase |
| 08 | [Markdown](../rescue-plan/module-08-markdown-card.md) | not created | unresearched | Requires 02 and 04 | Card/detail phase |
| 09 | [Graph rendering](../rescue-plan/module-09-graph-rendering.md) | not created | unresearched | Requires 01 and 05 | Card/detail phase |
| 10 | [Climate detail](../rescue-plan/module-10-climate-detail.md) | not created | unresearched | Requires 03, 05, and 06 | Card/detail phase |
| 11 | [Fan detail](../rescue-plan/module-11-fan-detail.md) | not created | unresearched | Requires 05 and 06 | Card/detail phase |

## Files

- [`module-workflow.md`](module-workflow.md): researcher, implementer, and
  verifier responsibilities plus copyable prompts.
- [`evidence-packet-template.md`](evidence-packet-template.md): canonical human
  packet structure for later modules.
- [`manifests/`](manifests/): reviewed TypeScript/runtime seeds and traversal
  boundaries.
- [`generated/`](generated/): deterministic dependency graphs. These are
  rebuildable candidate-discovery artifacts, not behavioral conclusions.
- Root `AGENTS.md`: concise phase routing and maintenance rules for this richer
  workflow. Keep operational detail here rather than expanding root context.

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

Run the checker first. Rebuild only on yellow/red or after deliberately changing
the manifest/resolver. A moved reference `HEAD` alone does not invalidate the
packet; anchored content hashes decide whether targeted research is required.
