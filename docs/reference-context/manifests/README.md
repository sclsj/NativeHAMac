# Module dependency manifests

Create one reviewed JSON manifest per module. Copy the shape of
`module-02.inputs.json`; do not generate seeds by indexing all of `src` or
`node_modules`.

Each entry is a reference-repository-relative file plus optional top-level
symbols:

```json
{
  "schemaVersion": "nativeha-reference-inputs/v1",
  "module": "NN",
  "title": "Module title",
  "nativeEntries": [
    { "path": "Sources/NativeHACore/Owner.swift", "symbols": ["OwnerType"] }
  ],
  "entries": [
    { "path": "src/path/entry.ts", "symbols": ["behaviorEntryPoint"] },
    { "path": "node_modules/package/dist/runtime.js", "symbols": ["RuntimeOwner"] }
  ],
  "followPackages": ["only-packages-whose-internals-matter"],
  "followTypeOnly": false,
  "maxDepth": 6,
  "maxNodes": 5000
}
```

Seed behavior entrypoints, not entire subsystems. Add a package runtime seed
when calls are made through an imported type/interface or dependency injection;
an import graph cannot infer that relationship. Explain each such crossing in
the evidence packet.

Keep `followTypeOnly` false unless decoding/model shape research actually
requires a declaration closure. Type edges are still recorded as boundaries.
`maxDepth` and `maxNodes` are safety ceilings, not behavioral stopping rules.
Extend or explicitly reseed any behavior-relevant trace that reaches a ceiling.
If a graph is truncated, do not promote the packet to `research-ready`.
