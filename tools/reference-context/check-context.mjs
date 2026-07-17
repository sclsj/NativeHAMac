#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

function git(root, args, fallback = null) {
  try {
    return execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return fallback;
  }
}

function usage() {
  process.stderr.write(
    "Usage: node tools/reference-context/check-context.mjs GRAPH.json [--strict]\n"
  );
  process.exit(2);
}

const args = process.argv.slice(2);
if (!args.length) usage();
const graphPath = resolve(args[0]);
const strict = args.includes("--strict");
const graph = JSON.parse(readFileSync(graphPath, "utf8"));
const nativeRoot = git(process.cwd(), ["rev-parse", "--show-toplevel"], process.cwd());
const referenceRoot = graph.reference.root;
const red = [];
const yellow = [];
const notes = [];

function compareCritical(label, path, expected) {
  if (!path || !existsSync(path)) {
    red.push(`${label} is missing: ${path}`);
    return;
  }
  const actual = sha256(readFileSync(path));
  if (actual !== expected) red.push(`${label} changed: expected ${expected}, found ${actual}`);
}

compareCritical("resolver", join(nativeRoot, graph.tool.path), graph.tool.sha256);
if (graph.manifest) compareCritical("manifest", join(nativeRoot, graph.manifest.path), graph.manifest.sha256);
compareCritical("tsconfig", join(referenceRoot, graph.reference.tsconfig.path), graph.reference.tsconfig.sha256);
if (graph.reference.lockfile.path) {
  compareCritical(
    "lockfile",
    join(referenceRoot, graph.reference.lockfile.path),
    graph.reference.lockfile.sha256
  );
}
if (graph.reference.rspackConfig) {
  compareCritical(
    "Rspack configuration",
    join(referenceRoot, graph.reference.rspackConfig.path),
    graph.reference.rspackConfig.sha256
  );
}

for (const node of graph.nodes) {
  const path = isAbsolute(node.path) ? node.path : join(referenceRoot, node.path);
  if (!existsSync(path)) {
    red.push(`source anchor disappeared: ${node.id}`);
    continue;
  }
  const actual = sha256(readFileSync(path));
  if (actual !== node.sha256) yellow.push(`source anchor changed: ${node.id}`);
  if (node.kind === "npm" && node.package) {
    const packageRoot = join(referenceRoot, "node_modules", ...node.package.name.split("/"));
    const canonicalPackageJSON = join(packageRoot, "package.json");
    if (!existsSync(canonicalPackageJSON)) red.push(`package disappeared: ${node.package.name}`);
    else if (sha256(readFileSync(canonicalPackageJSON)) !== node.package.packageJSONSha256) {
      red.push(`package identity changed: ${node.package.name}@${node.package.version}`);
    }
  }
}

for (const anchor of graph.nativeha?.anchors || []) {
  const path = join(nativeRoot, anchor.path);
  if (!existsSync(path)) {
    red.push(`NativeHA source anchor disappeared: ${anchor.path}`);
    continue;
  }
  const actual = sha256(readFileSync(path));
  if (actual !== anchor.sha256) yellow.push(`NativeHA source anchor changed: ${anchor.path}`);
}

const currentHead = git(referenceRoot, ["rev-parse", "HEAD"]);
if (currentHead !== graph.reference.gitHead) {
  notes.push(`reference HEAD moved ${graph.reference.gitHead} -> ${currentHead}; anchored files decide staleness`);
}
const currentNativeHead = git(nativeRoot, ["rev-parse", "HEAD"]);
if (graph.nativeha?.gitHead && currentNativeHead !== graph.nativeha.gitHead) {
  notes.push(`NativeHA HEAD moved ${graph.nativeha.gitHead} -> ${currentNativeHead}; anchored files decide staleness`);
}
if (graph.unresolved.length) yellow.push(`graph contains ${graph.unresolved.length} unresolved/nonliteral edges`);
if (graph.truncated) red.push(`graph was truncated: ${JSON.stringify(graph.truncated)}`);

const status = red.length ? "red" : yellow.length ? "yellow" : "green";
process.stdout.write(`${status.toUpperCase()}: ${graphPath}\n`);
for (const item of red) process.stdout.write(`RED: ${item}\n`);
for (const item of yellow) process.stdout.write(`YELLOW: ${item}\n`);
for (const item of notes) process.stdout.write(`NOTE: ${item}\n`);
if (red.length) process.exitCode = 3;
else if (strict && yellow.length) process.exitCode = 2;
