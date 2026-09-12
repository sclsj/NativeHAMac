#!/usr/bin/env node
// Research/test tooling only. Never used by the native application.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const args = process.argv.slice(2);
assert(
  args.length <= 2 && ["--check", "--write"].includes(args[0]),
  "Usage: node tools/markdown-reference/oracle.mjs --check|--write [reference-checkout]",
);
const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const reference = path.resolve(
  args[1] || "/Users/jin/Documents/HA/hass-frontend",
);
const fixtureDir = path.join(root, "Tests/Fixtures/Markdown");
const fixturePath = path.join(fixtureDir, "cases.json");
const expectedPath = path.join(fixtureDir, "expected-worker.json");
const requireReference = createRequire(path.join(reference, "package.json"));
const ts = requireReference("typescript");
const { marked } = await import(
  pathToFileURL(requireReference.resolve("marked")).href
);
const xss = requireReference("xss");
const read = (relative) =>
  fs.readFileSync(path.join(reference, relative), "utf8");
const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const sourcePath = "src/resources/markdown-worker.ts";
const source = read(sourcePath);
// Strip only known import declarations and replace only the RPC export call.
// Fail closed if the upstream entry point changes, rather than approximating it.
const expectedImports = [
  'import { expose } from "comlink";',
  'import type { MarkedOptions } from "marked";',
  'import { marked } from "marked";',
  'import type { IWhiteList } from "xss";',
  'import { filterXSS, getDefaultWhiteList } from "xss";',
];
let adapted = source;
for (const declaration of expectedImports) {
  assert.equal(
    adapted.split(declaration).length,
    2,
    `Changed import: ${declaration}`,
  );
  adapted = adapted.replace(declaration, "");
}
assert.equal(adapted.split("expose(api);").length, 2, "Changed RPC export");
adapted = adapted.replace("expose(api);", "return api;");
const compiled = ts.transpileModule(adapted, {
  compilerOptions: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.CommonJS,
  },
}).outputText;
const api = new Function(
  "marked",
  "filterXSS",
  "getDefaultWhiteList",
  "exports",
  compiled,
)(marked, xss.filterXSS, xss.getDefaultWhiteList, {});
const cases = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
assert.equal(cases.schemaVersion, 1);
const ids = new Set();
const results = [];
for (const fixture of cases.cases) {
  assert.match(fixture.id, /^[a-z0-9-]+$/);
  assert(!ids.has(fixture.id), `Duplicate fixture ${fixture.id}`);
  ids.add(fixture.id);
  assert.equal(typeof fixture.source, "string");
  assert(["core", "deferred", "sanitizer"].includes(fixture.category));
  assert.equal(typeof fixture.note, "string");
  if (fixture.category === "deferred")
    assert.equal(fixture.nativeFallback, "visible-inert-source");
  const fragments = await api.renderMarkdown(
    fixture.source,
    { breaks: true, gfm: true },
    {
      allowSvg: false,
      allowDataUrl: false,
    },
  );
  assert(
    Array.isArray(fragments) &&
      fragments.every((value) => typeof value === "string"),
  );
  const html = fragments.join("");
  for (const needle of fixture.mustContain || [])
    assert(html.includes(needle), `${fixture.id}: missing ${needle}`);
  for (const needle of fixture.mustNotContain || [])
    assert(!html.includes(needle), `${fixture.id}: unexpected ${needle}`);
  results.push({ id: fixture.id, fragments, html });
}
const anchors = [
  sourcePath,
  "src/components/ha-markdown-element.ts",
  "src/components/ha-markdown.ts",
  "src/panels/lovelace/cards/hui-markdown-card.ts",
  "src/common/dom/is-navigation-click.ts",
  "src/panels/lovelace/common/directives/action-handler-directive.ts",
  "node_modules/marked/lib/marked.esm.js",
  "node_modules/xss/lib/index.js",
  "node_modules/xss/lib/default.js",
  "node_modules/xss/lib/parser.js",
  "node_modules/xss/lib/xss.js",
  "node_modules/xss/lib/util.js",
];
const expected = {
  schemaVersion: 1,
  boundary:
    "Exact markdown-worker sanitized HTML; excludes DOM postprocessing, CSS, navigation, actions and native fallback execution",
  revision: execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: reference,
    encoding: "utf8",
  }).trim(),
  dependencies: Object.fromEntries(
    ["marked", "xss", "typescript"].map((name) => [
      name,
      JSON.parse(read(`node_modules/${name}/package.json`)).version,
    ]),
  ),
  sourceHashes: Object.fromEntries(
    anchors.map((anchor) => [anchor, sha256(read(anchor))]),
  ),
  fixtureHash: sha256(fs.readFileSync(fixturePath)),
  options: {
    marked: { breaks: true, gfm: true },
    hass: { allowSvg: false, allowDataUrl: false },
  },
  results,
};
const serialized = JSON.stringify(expected, null, 2) + "\n";
if (args[0] === "--write") fs.writeFileSync(expectedPath, serialized);
else
  assert.equal(
    serialized,
    fs.readFileSync(expectedPath, "utf8"),
    "Reference outputs/anchors changed; review before --write",
  );
console.log(
  `${args[0]}: ${results.length} fixtures validated; ${expected.revision}; marked ${expected.dependencies.marked}, xss ${expected.dependencies.xss}`,
);
