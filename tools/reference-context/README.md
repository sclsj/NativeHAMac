# Reference-context tools

These scripts turn a small, reviewed module manifest into a deterministic
TypeScript dependency graph. They use the exact TypeScript installation and
`tsconfig.json` from `/Users/jin/Documents/HA/hass-frontend`; they install no
packages and never modify the reference repository.

## Commands

```sh
node tools/reference-context/trace-ts-deps.mjs \
  --manifest docs/reference-context/manifests/module-02.inputs.json \
  --out-json docs/reference-context/generated/module-02.dependencies.json \
  --out-markdown docs/reference-context/generated/module-02.dependencies.md

node tools/reference-context/check-context.mjs \
  docs/reference-context/generated/module-02.dependencies.json

node tools/reference-context/test-resolver.mjs
```

Set `HASS_FRONTEND_ROOT` or pass `--reference-root` if the reference checkout
moves. `check-context.mjs` reports:

- green when all anchored inputs still match;
- yellow when an anchored source file changed or the graph contains an
  unresolved dynamic edge, requiring a targeted reread;
- red when the resolver, manifest, compiler/build configuration, lockfile,
  package identity, or source location disappeared or changed structurally.

The graph is candidate-discovery output, not a claim of behavioral equivalence.
Calls through interfaces and types can cross boundaries that imports cannot
discover. Add those implementation files explicitly to the module manifest and
explain the boundary in the human evidence packet.
