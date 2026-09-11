# Verification route

Independently review already-completed work. Do not edit application code unless the request also asks for repairs or implementation; add tests only when test edits are authorized.

- Inspect the changed execution paths and tests; earlier audits do not rule out later regressions. For staged work, follow the packet workflow and report by contract ID. Mark complete only with evidence for every applicable gate.
- Run relevant deterministic tests, read-only live smoke, and lifecycle, concurrency, responsiveness, or performance checks. State which checks were not performed and distinguish expected failures/skips from passing coverage.
- For UI changes, follow `docs/visual-testing.md`. Compare NativeHA and the reference under comparable data and presentation conditions; inspect interaction/animation states as well as final output. Verify slow work does not block dismissal or unrelated controls. Ask for a bounded manual capture only when it cannot be obtained through available tools.
- For algorithm/cache changes, rerun the relevant tracked benchmark with live `1h` and `24h` data, including cold/warm behavior where applicable and correctness, CPU, and memory. Preserve rendering fidelity.
- Record exact failures, evidence, remaining gaps, and the next action in the applicable packet or standalone review. Read-only live HA checks are allowed; state-changing service tests require an explicitly authorized safe target.
