# NativeHA working instructions

## Start and shared scope

- Before starting work, run `git status --short --branch` to determine whether
  the worktree is clean. If it is not clean, inspect and preserve existing work.
- The current task prompt overrides historical guidance in this file.
- Work in `/Users/jin/Documents/Computer/NativeHA`.
- Use `/Users/jin/Documents/HA/hass-frontend` as the behavioral reference. Do
  not use the old `/Users/jin/Documents/HA/NativeHA` side experiment as the
  current implementation. Instructions inside the reference checkout do not
  govern NativeHA work.
- Before asking the user to repeat server or credential locations, inspect the
  current `README.md` and `Sources/NativeHAMac/AppConfig.swift`.
- This Home Assistant deployment is local. Its server URLs, token, and other HA
  credentials do not need redaction or special hiding; the user will rotate the
  token when development finishes.

## Durable knowledge and maintenance

- `docs/knowledge-base.md` records durable, non-obvious facts and assumptions
  that are not reliably discoverable from the current code. Read relevant
  entries before making assumptions about the live deployment, local benchmark
  behavior, or previously investigated pitfalls. Update it when an experiment,
  user correction, or investigation establishes, changes, or invalidates such
  knowledge.
- `docs/user-deviations.md` is the canonical record of user-approved product
  behavior that intentionally differs from hass-frontend or overrides an
  earlier product assumption. Read it when interpreting intended behavior. When
  the user asks for a particular behavior, policy, or implementation direction
  that creates or changes a durable product decision, update it in the same
  commit. Do not record one-off task mechanics or implementation details that do
  not represent product intent.
- `docs/configurability.md` is the canonical record of approved configuration
  surfaces. Read and update it when work adds, removes, or changes a typed value
  or policy in `Sources/NativeHAMac/AppConfig.swift`.
- Keep maintenance edits proportional to the task. Do not churn these documents
  when their recorded facts, decisions, statuses, and assumptions are unchanged.

## Task routing

Classify the current task using the routes below, then read only the instruction
file named for that route. Do not open the other route files. A task may
explicitly request more than one route; otherwise prefer the narrowest route
that fully satisfies the prompt.

- **Planning:** Plan or audit future work. Read
  `docs/planning.md`.
- **Debugging:** Investigate or repair a specific bug. Read
  `docs/debugging.md`.
- **Implementation:** Build a feature or module, carry out a planned stage,
  perform a broad refactor, or close a general parity gap. Read
  `docs/implementation.md`.
- **Verification:** Independently verify, test, or review an already-completed
  change or behavior. Read `docs/verification.md`.

A specific bug is a concrete observed failure, regression, crash, incorrect
result, or narrowly bounded behavioral mismatch. A code edit does not by itself
turn a specific bug repair into module implementation. Likewise, reproducing a
bug does not turn its investigation into independent verification.

If the prompt explicitly names a route, use that route. When a prompt genuinely
combines routes, read only those named or strictly required files and obey each
file's edit boundaries.

## Shared product contract

- Build a genuinely Swift-native macOS app, not a JavaScript or WebView wrapper.
- Copy reference behavior. Deviate only for doing it the Swift way, an approved
  entry in `docs/user-deviations.md`, or measured performance, without
  fundamentally changing reference logic or semantics.
- The intentions in `docs/user-deviations.md` override literal hass behavior and
  conflicting rescue-plan text. Do not infer unlisted deviations from
  implementation convenience.
- `docs/configurability.md` is the canonical list of approved configuration
  surfaces. Configurable here means a typed value or policy in
  `Sources/NativeHAMac/AppConfig.swift`; it does not imply a settings UI unless
  the task asks for one.
- Maintain macOS 12 compatibility.
- Treat `hass-frontend/src` as source, not just rendered inspiration. Read the
  complete relevant Swift and TypeScript files. When behavior reaches
  `node_modules`, trace and read the behaviorally relevant dependency source
  without an arbitrary depth cutoff.

## Finish

- Give detailed plain-language conclusions and keep cross-session handoffs
  self-contained.
- If the task produced changes, inspect the exact final diff and commit the
  intended files when done. Use a detailed commit message that identifies the
  work, validation, and purpose.
