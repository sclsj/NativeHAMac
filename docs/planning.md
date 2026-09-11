# Planning route

Plan or audit readiness without editing application code unless the request also asks for repairs or implementation.

- Start staged rescue work with `docs/rescue-plan/README.md` and the `docs/reference-context/README.md` status index. Verify relevant claims against current code, tests, approved product decisions, and live behavior where needed. Distinguish confirmed bugs, technical debt, planned gaps, and unverified risks.
- For module research, follow `docs/reference-context/module-workflow.md`. Use the reviewed manifest and `tools/reference-context/trace-ts-deps.mjs` for discovery, adding explicit runtime seeds where types/imports hide behavior. Keep generated graphs out of prompt context; write reviewed contracts and source anchors in the human packet.
- Keep repair/module plans bounded and self-contained. Prioritize behavior used by the live dashboard. An audit need not refresh every module packet; refresh only evidence needed for its conclusions or next implementation.
- Use bounded read-only subagents when independent source audits can run alongside useful local work. Keep one owner for shared documentation edits and consolidate findings with their confidence and validation limits.
