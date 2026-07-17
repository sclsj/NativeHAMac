---
schema: nativeha-evidence/v1
module: "NN"
title: Replace with module title
plan: ../../rescue-plan/module-NN-name.md
status: unresearched
contract_revision: 0
depends_on: []
reference_revision: ""
nativeha_revision: ""
graph_file: ../generated/module-NN.dependencies.json
graph_fingerprint: ""
last_validated: YYYY-MM-DD
---

# Module NN evidence packet

## Scope delta

Record only refinements, corrections, and unresolved ambiguity relative to the
rescue plan. Do not copy the plan.

## Behavior contracts

| ID | Trigger/input | Observable behavior | Ordering/lifecycle/error rules | Evidence | Swift owner | Verification |
|---|---|---|---|---|---|---|
| CNN-01 | | | | | | |

## Source anchors

Identify repository source by revision, relative path, symbol, content hash or
Git blob, and a line hint. For npm code, record package version, package and lock
identity, package-relative path, symbol, and content hash. Line positions are
navigation hints only.

## Dependency traces and boundaries

For each behavior-relevant trace, record the entrypoint, graph nodes, runtime
versus type-only edges, why traversal entered a dependency, and its stop
boundary. Link the full generated graph rather than copying it.

## Native mapping

| Contract | Existing/planned Swift path | Symbol/type | Ownership/state | Notes |
|---|---|---|---|---|

## Decisions and native deviations

| ID | Decision/deviation | Allowed reason | Preserved semantics | Evidence | Test | Status |
|---|---|---|---|---|---|---|

Allowed reasons are native-platform convention, platform limitation, or a
measured performance benefit. Every deviation identifies preserved semantics
and verification.

## Validation

### Offline deterministic tests

### Read-only live smoke

### Visual and animation oracle

State explicit `N/A` with a reason for nonvisual modules.

### Performance and lifecycle

## Open questions and risks

## Handoff

Record the exact next action, expected files, outstanding contracts/tests, and
known limitations before the phase ends or the task is compacted.

## Change log
