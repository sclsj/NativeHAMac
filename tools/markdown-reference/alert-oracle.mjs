#!/usr/bin/env node
// Exact HA alert conversion branch over jsdom, not a browser/layout oracle.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
const args = process.argv.slice(2);
assert(
  args.length <= 2 && ["--check", "--write"].includes(args[0]),
  "Usage: alert-oracle.mjs --check|--write [reference-checkout]",
);
const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const reference = path.resolve(
  args[1] || "/Users/jin/Documents/HA/hass-frontend",
);
const require = createRequire(path.join(reference, "package.json"));
const ts = require("typescript");
const { JSDOM } = require("jsdom");
const xss = require("xss");
const { marked } = await import(pathToFileURL(require.resolve("marked")).href);
const read = (p) => fs.readFileSync(path.join(reference, p), "utf8");
const sha = (data) => createHash("sha256").update(data).digest("hex");
const transpile = (s) =>
  ts.transpileModule(s, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.CommonJS,
    },
  }).outputText;
const workerSource = read("src/resources/markdown-worker.ts");
assert.equal(workerSource.split("expose(api);").length, 2);
const worker = new Function(
  "marked",
  "filterXSS",
  "getDefaultWhiteList",
  "exports",
  transpile(
    workerSource
      .replace(/^import .*;\n/gm, "")
      .replace("expose(api);", "return api;"),
  ),
)(marked, xss.filterXSS, xss.getDefaultWhiteList, {});
const elementSource = read("src/components/ha-markdown-element.ts");
const constantStart = elementSource.indexOf("const _gitHubMarkdownAlerts =");
const constantEnd = elementSource.indexOf("\n@customElement", constantStart);
const branchStart = elementSource.indexOf("        const gitHubAlertMatch =");
const branchEnd = elementSource.indexOf("      } else if (", branchStart);
assert(
  constantStart >= 0 &&
    constantEnd > constantStart &&
    branchStart >= 0 &&
    branchEnd > branchStart,
  "Changed alert source structure",
);
const extracted =
  elementSource.slice(constantStart, constantEnd) +
  "\n" +
  elementSource.slice(branchStart, branchEnd);
const convert = new Function(
  "node",
  "document",
  "walker",
  transpile(extracted),
);
const cases = JSON.parse(
  fs.readFileSync(
    path.join(root, "Tests/Fixtures/Markdown/alert-cases.json"),
    "utf8",
  ),
);
assert.equal(cases.schemaVersion, 1);
const results = [];
const ids = new Set();
for (const fixture of cases.cases) {
  assert(!ids.has(fixture.id));
  ids.add(fixture.id);
  const html = (
    await worker.renderMarkdown(
      fixture.source,
      { breaks: true, gfm: true },
      { allowSvg: false, allowDataUrl: false },
    )
  ).join("");
  const dom = new JSDOM(html);
  const document = dom.window.document;
  const walker = document.createTreeWalker(
    document.body,
    dom.window.NodeFilter.SHOW_ELEMENT,
    null,
  );
  while (walker.nextNode())
    if (walker.currentNode instanceof dom.window.HTMLQuoteElement)
      convert.call({ breaks: true }, walker.currentNode, document, walker);
  const alerts = Array.from(document.querySelectorAll("ha-alert")).map(
    (node) => ({
      type: node.alertType,
      html: node.innerHTML,
      text: node.textContent,
    }),
  );
  assert.deepEqual(alerts, fixture.expectedAlerts, fixture.id);
  results.push({
    id: fixture.id,
    workerHTML: html,
    postprocessedHTML: document.body.innerHTML,
    alerts,
  });
  dom.window.close();
}
const anchors = [
  "src/resources/markdown-worker.ts",
  "src/components/ha-markdown-element.ts",
  "node_modules/marked/lib/marked.esm.js",
  "node_modules/xss/lib/default.js",
  "node_modules/xss/lib/xss.js",
  "node_modules/xss/lib/parser.js",
  "node_modules/jsdom/lib/api.js",
];
const expected = {
  schemaVersion: 1,
  boundary:
    "Exact extracted HA breaks=true alert branch and worker, executed over jsdom HTML parser/TreeWalker; not browser CSS, custom-element runtime or visual evidence",
  revision: execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: reference,
    encoding: "utf8",
  }).trim(),
  dependencies: Object.fromEntries(
    ["marked", "xss", "jsdom", "typescript"].map((name) => [
      name,
      JSON.parse(read(`node_modules/${name}/package.json`)).version,
    ]),
  ),
  sourceHashes: Object.fromEntries(anchors.map((p) => [p, sha(read(p))])),
  extractedBranchHash: sha(extracted),
  fixtureHash: sha(
    fs.readFileSync(
      path.join(root, "Tests/Fixtures/Markdown/alert-cases.json"),
    ),
  ),
  results,
};
const output = JSON.stringify(expected, null, 2) + "\n";
const target = path.join(root, "Tests/Fixtures/Markdown/expected-alerts.json");
if (args[0] === "--write") fs.writeFileSync(target, output);
else
  assert.equal(
    output,
    fs.readFileSync(target, "utf8"),
    "Alert oracle changed; review before --write",
  );
console.log(
  `${args[0]}: ${results.length} alert cases validated; jsdom ${expected.dependencies.jsdom}; exact extracted branch ${expected.extractedBranchHash}`,
);
