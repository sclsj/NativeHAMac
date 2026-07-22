# Planning route

Use this route only to plan or audit future work. Do not make application-code
edits unless the current prompt explicitly adds the implementation route.

- Start staged rescue planning with `docs/rescue-plan/README.md`, but verify its
  claims against current code, live behavior, `docs/user-deviations.md`, and
  `docs/configurability.md`.
- Use `docs/reference-context/README.md` as the durable module evidence and
  handoff index. For a missing or stale packet, create or refresh the reviewed
  module manifest, generated dependency graph, and human evidence packet by
  following `docs/reference-context/module-workflow.md`.
- Resolve reference sources with `tools/reference-context/trace-ts-deps.mjs`
  through a module manifest instead of manually crawling all of
  `hass-frontend`. Record repository revision, relative path, stable symbol,
  and blob/content hash; line numbers are navigation hints only. Calls through
  types or dependency injection may require an explicit reviewed runtime seed.
- Keep generated graphs rebuildable and out of prompt context. Promote only
  behavior-relevant contracts, anchors, decisions, risks, and unresolved
  questions into the human evidence packet.
- Keep stages or modules small enough for one bounded agent/session. Make plans
  descriptive and self-contained enough for a later implementation session.
- Maintain durable reference indexes and rescue/action-plan artifacts. Focus
  first on the behavior, entities, and cards used by the live configuration.
- Use bounded high/xhigh subagents for read-heavy audits or planning when source
  discovery would otherwise consume the future implementation context.
- Retain setup facts already supplied. Ask about material product choices, not
  repeatedly about established setup.
- Update `docs/knowledge-base.md` when planning research confirms, refines, or
  invalidates a durable, non-obvious deployment assumption, local measurement,
  or recurring reasoning pitfall.

Before a handoff, compaction, or session end, update the applicable module
evidence packet with status, decisions, actual artifact scope, validation,
remaining gaps, and the exact next action.
