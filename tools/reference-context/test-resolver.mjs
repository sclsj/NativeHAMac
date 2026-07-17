#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
}).trim();
const temporary = mkdtempSync(join(tmpdir(), "nativeha-reference-context-"));
const output = join(temporary, "graph.json");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

try {
  execFileSync(
    process.execPath,
    [
      resolve(repoRoot, "tools/reference-context/trace-ts-deps.mjs"),
      "--manifest",
      "docs/reference-context/manifests/module-02.inputs.json",
      "--out-json",
      output,
    ],
    { cwd: repoRoot, stdio: ["ignore", "ignore", "pipe"] }
  );
  const graph = JSON.parse(readFileSync(output, "utf8"));
  assert(graph.schemaVersion === "nativeha-ts-dependency-graph/v1", "unexpected graph schema");
  assert(!graph.truncated, "module-02 graph was truncated");
  assert(graph.unresolved.length === 0, "module-02 graph contains unresolved edges");
  const expectedNativeAnchors = [
    "Sources/NativeHACore/HomeAssistantWebSocketClient.swift",
    "Sources/NativeHACore/HomeAssistantWebSocketConnection.swift",
    "Sources/NativeHACore/HomeAssistantWebSocketTransport.swift",
    "Sources/NativeHAMac/AppConfig.swift",
    "Sources/NativeHAMac/DashboardViewModel.swift",
  ];
  assert(
    expectedNativeAnchors.every((path) =>
      graph.nativeha.anchors.some((anchor) => anchor.path === path)
    ),
    "NativeHA anchors were not recorded"
  );
  assert(graph.nativeha.anchors.every((anchor) => !anchor.missing), "a NativeHA anchor is missing");
  assert(
    graph.nodes.filter((node) => node.explicitSeed).every((node) => node.missingSymbols.length === 0),
    "an explicit seed symbol did not resolve"
  );
  const coreRuntime = graph.edges.find(
    (edge) =>
      edge.from === "repo:src/entrypoints/core.ts" &&
      edge.specifier === "home-assistant-js-websocket" &&
      edge.phase === "runtime"
  );
  assert(coreRuntime, "missing core runtime package edge");
  assert(coreRuntime.typeResolved.endsWith("dist/index.d.ts"), "missing declaration resolution");
  assert(coreRuntime.runtimeResolved.endsWith("dist/index.js"), "missing package runtime resolution");
  const historyType = graph.edges.find(
    (edge) =>
      edge.from === "repo:src/data/history.ts" &&
      edge.specifier === "home-assistant-js-websocket" &&
      edge.phase === "type"
  );
  assert(historyType?.boundary === "type-only-not-followed", "history type boundary changed");
  assert(
    graph.edges.some(
      (edge) =>
        edge.from === "npm:home-assistant-js-websocket@9.6.0:dist/connection.js" &&
        edge.to === "npm:home-assistant-js-websocket@9.6.0:dist/messages.js"
    ),
    "package implementation closure did not include messages.js"
  );
  process.stdout.write(
    `PASS: ${graph.nodes.length} nodes, ${graph.edges.length} edges, ${graph.graphFingerprint}\n`
  );
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
