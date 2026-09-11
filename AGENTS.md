# NativeHA working instructions

## Start and sources of truth

- Work in `/Users/jin/Documents/Computer/NativeHA`. First run `git status --short --branch`; inspect and preserve existing work.
- The current task overrides historical guidance. Files under `docs/agent-history/` and `docs/agent-history-authored/` are archives, not active instructions.
- Use `/Users/jin/Documents/HA/hass-frontend` as the read-only behavioral reference. Its instructions do not govern NativeHA. The old `/Users/jin/Documents/HA/NativeHA` experiment is not this implementation.
- Before asking for server or credential locations, inspect `README.md` and `Sources/NativeHAMac/AppConfig.swift`. This is a local HA deployment; its URLs and credentials need no special redaction. The user will rotate the token after development.

## Product contract and durable records

- Build a Swift-native macOS app using native APIs, maintaining macOS 12 compatibility. Do not use JavaScript or a WebView as the app architecture.
- Preserve observable hass-frontend semantics. Native implementation choices and measured performance improvements must preserve those semantics; intentional product differences require user approval.
- `docs/user-deviations.md` records approved differences and overrides conflicting reference behavior or rescue-plan text. Read it when interpreting intended behavior; update it when a user decision changes that behavior.
- `docs/configurability.md` records approved configuration surfaces, including future intent. Read it when changing configuration and keep implementation notes synchronized. Configuration means typed values or policies in `AppConfig.swift`, not a settings UI unless requested.
- Read relevant `docs/knowledge-base.md` entries before making deployment, benchmark, or previously investigated assumptions. Update only durable, non-obvious facts established or invalidated by the work.
- Keep these records proportional to the change; do not repeat unchanged facts in every document. Current code and fresh evidence establish implementation status; plans and green source hashes alone do not prove correctness.

## Task routing

Read the narrowest applicable route. Combine routes only when the request requires it. Reviewing the instructions themselves permits reading/editing the instruction files without invoking their application-code workflows.

| Request | Route |
|---|---|
| Plan or audit project readiness/future work | `docs/planning.md` |
| Investigate or repair a specific observed failure | `docs/debugging.md` |
| Build a feature, planned stage, broad refactor, or general parity work | `docs/implementation.md` |
| Independently verify an already-completed change or behavior | `docs/verification.md` |

Follow an explicitly requested route. A bug repair remains debugging even when it edits code; reproducing a bug does not require the verification route. Audit/diagnosis requests authorize evidence gathering and documentation, not application-code repairs. A request to fix or implement authorizes those edits without requiring the user to name a route.

## Reference research and finish

- Read complete relevant Swift and TypeScript files when investigating or changing behavior. Follow behaviorally relevant runtime dependencies into `node_modules`; stop at a platform primitive, established API contract, or irrelevant edge, not an arbitrary depth. A fresh module packet narrows the relevant path; it does not replace reading the code being changed.
- Use `docs/reference-context/module-workflow.md` for packet-backed staged work and `docs/visual-testing.md` when visual/performance testing applies. Update an existing packet only when its scope, contracts, decisions, status, validation, or next action changes. Standalone work needs no new packet.
- Give plain-language conclusions with evidence, limitations, and a self-contained next action. If files changed, inspect the exact final diff and commit the intended files with a message explaining purpose, work, and validation. Include applicable durable-record updates in the same commit.
