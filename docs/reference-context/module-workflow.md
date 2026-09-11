# Reference-parity module workflow

Use this workflow for staged, packet-backed module work. Root `AGENTS.md` defines product precedence, task authorization, and durable-record maintenance. The current packet refines the historical rescue plan; record disagreements explicitly rather than silently inheriting stale plan requirements.

## 1. Research

Research when the packet is missing, incomplete, or stale. A delegated researcher is read-only on Swift and may update its manifest, generated graph, and evidence packet. The task owner reconciles plan/index changes.

1. Read the module plan and existing packet. Run `check-context.mjs` if a graph exists; see `tools/reference-context/README.md` for commands and statuses.
2. Trace relevant behavior through reviewed entrypoints and runtime seeds with `trace-ts-deps.mjs`. Read the complete relevant files, including dependency implementation where it determines the contract.
3. Record observable contracts, Swift owners, applicable validation, risks, and source anchors using the evidence-packet template. Pin revision, relative path, symbol, and content hash; line numbers are navigation hints.
4. Set `research-ready` when no material behavior question blocks the scoped implementation. Obtain independent research review when the stage requires that gate.

## 2. Implementation

1. Run the staleness check. A green result establishes anchored source freshness, not behavioral correctness. On yellow/red, resolve affected evidence before dependent edits; unrelated authorized work may continue.
2. Read the packet's current scope, contracts, and relevant source files. Read the historical plan only for scope the packet leaves unresolved. Do not repeat the broad reference audit when the packet is fresh.
3. Implement and test in dependency order with one Swift-writing owner. Record native decisions and preserved semantics; product deviations still require the root user-approval contract.
4. Run targeted tests and the full applicable deterministic suite. Record actual changes, validation, and unresolved gaps. Set `verification-ready` and provide the exact independent-verifier handoff.

## 3. Independent verification

1. Inspect the implementation diff, packet contracts, and relevant source/tests. Run source staleness and resolver self-tests.
2. Run targeted/full deterministic tests and applicable read-only live checks. State-changing HA tests require an explicitly authorized safe target.
3. For visual modules, follow `docs/visual-testing.md` and compare matching reference/native states. Document approximations and untested interactions.
4. Record results by contract ID. Set `complete` only when applicable gates pass; otherwise keep `verification-ready` with precise failures.

## Handoffs

Use bounded read-only research and independent verifier subagents when useful; the task owner integrates their evidence and preserves a single code owner. Keep generated graphs and raw build output out of prompts. Update the packet's handoff before a phase ends or compaction: status, decisions, actual artifact scope, validation, remaining gaps, and exact next action. Do not append an unchanged handoff merely because another turn ended.
