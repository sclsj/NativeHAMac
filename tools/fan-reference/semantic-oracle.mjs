#!/usr/bin/env node
// Execute exact reference declarations/methods, not a second copy of the formulas.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const reference = process.env.HA_REFERENCE_ROOT || "/Users/jin/Documents/HA/hass-frontend";
const ts = createRequire(path.join(reference, "package.json"))("typescript");
const sources = {}, extractions = {};
function read(relative) {
  const source = fs.readFileSync(path.join(reference, relative), "utf8");
  sources[relative] = createHash("sha256").update(source).digest("hex");
  return ts.createSourceFile(relative, source, ts.ScriptTarget.Latest, true);
}
function top(parsed, name) {
  const matches = parsed.statements.filter(node => node.name?.text === name ||
    (ts.isVariableStatement(node) && node.declarationList.declarations.some(item => item.name.getText(parsed) === name)));
  assert.equal(matches.length, 1, `Declaration ${name}`);
  return matches[0].getText(parsed).replace(/^export /, "");
}
function evaluate(source, bindings, names) {
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  return new Function(...Object.keys(bindings), compiled + `\nreturn {${names.join(",")}};`)(...Object.values(bindings));
}
const fanPath = "src/data/fan.ts";
const fanSource = read(fanPath);
const fanNames = ["FanEntityFeature", "FAN_SPEEDS", "FAN_SPEED_COUNT_MAX_FOR_BUTTONS", "computeFanSpeedCount", "fanPercentageToSpeed", "fanSpeedToPercentage"];
extractions[fanPath] = { declarations: fanNames };
const fan = evaluate(fanNames.map(name => top(fanSource, name)).join("\n"), {}, fanNames);

const sliderPath = "src/components/ha-control-slider.ts";
const sliderSource = read(sliderPath);
const declarations = sliderSource.statements.filter(node => ts.isClassDeclaration(node) && node.name?.text === "HaControlSlider");
assert.equal(declarations.length, 1);
const memberNames = ["valueToPercentage", "percentageToValue", "steppedValue", "boundedValue", "_isVisuallyInverted", "_getPercentageFromEvent", "_tenPercentStep", "_handleKeyDown", "_handleKeyUp"];
const methods = memberNames.map(name => {
  const matches = declarations[0].members.filter(node => node.name?.getText(sliderSource) === name);
  assert.equal(matches.length, 1, `Slider member ${name}`);
  assert.equal((ts.getDecorators?.(matches[0]) || []).length, 0);
  return matches[0].getText(sliderSource);
});
extractions[sliderPath] = { className: "HaControlSlider", declarations: ["A11Y_KEY_CODES"], members: memberNames };
const mainWindow = { document: { dir: "ltr" } };
const { HaControlSlider } = evaluate(`${top(sliderSource, "A11Y_KEY_CODES")}\nclass HaControlSlider {\n${methods.join("\n")}\n}`, {
  mainWindow,
  fireEvent: (owner, type, detail) => owner.events.push({ type, ...detail }),
}, ["HaControlSlider"]);
function slider(step, value = 37) {
  return Object.assign(new HaControlSlider(), {
    min: 0, max: 100, step, value, vertical: true, inverted: false, events: [],
    // Tooltip timing/DOM lifecycle are outside this pure numerical oracle.
    _showTooltip() {}, _hideTooltip() {},
  });
}
const countCases = [
  ["missing", {}], ["null", { percentage_step: null }],
  ...[100, 50, 100 / 3, 33, 25, 16, 22, 40, 0, -1, 201].map(step => [`step-${step}`, { percentage_step: step }]),
].map(([id, attributes]) => {
  const entity = { entity_id: "fan.fixture_oracle", state: "on", attributes };
  const count = fan.computeFanSpeedCount(entity);
  return { id, attributes, count,
    speeds: (fan.FAN_SPEEDS[count] ?? []).map(speed => ({ speed, percentage: fan.fanSpeedToPercentage(entity, speed) })),
    selections: [0, 0.4, 25, 33, 50, 66, 100].map(percentage => ({ percentage, speed: fan.fanPercentageToSpeed(entity, percentage) })),
  };
});
const pointerCases = [1, 25, 16, 22, 0].flatMap(step => [-20, 0, 64, 128, 320, 340].map(y => {
  const control = slider(step);
  const progress = control._getPercentageFromEvent({ center: { y }, target: { getBoundingClientRect: () => ({ top: 0 }), clientHeight: 320 } });
  const raw = control.percentageToValue(progress);
  return { step, y, progress, raw, stepped: control.steppedValue(raw) };
}));
const keyboardCases = [1, 16, 22].flatMap(step => ["ltr", "rtl"].flatMap(direction =>
  ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "PageUp", "PageDown", "Home", "End"].map(code => {
    const control = slider(step);
    mainWindow.document.dir = direction;
    const event = { code, preventDefault() {} };
    control._handleKeyDown(event); control._handleKeyUp(event);
    return { step, initial: 37, direction, code, value: control.value, events: control.events };
  })));
const output = {
  referenceRevision: execFileSync("git", ["-C", reference, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
  typescriptVersion: ts.version, sources, extractions,
  featureBits: Object.fromEntries(Object.entries(fan.FanEntityFeature).filter(([name]) => Number.isNaN(Number(name)))),
  discreteThreshold: fan.FAN_SPEED_COUNT_MAX_FOR_BUTTONS, countCases, pointerCases, keyboardCases,
};
const encoded = JSON.stringify(output, (_key, value) => typeof value === "number" && !Number.isFinite(value) ? { $number: String(value) } : Object.is(value, -0) ? { $number: "-0" } : value, 2) + "\n";
if (process.argv[2] === "--check") {
  assert.equal(encoded, fs.readFileSync(path.join(root, "Tests/Fixtures/Fan/expected-semantics.json"), "utf8"), "Fan reference output/source provenance changed");
  console.log("Fan semantic reference matches checked fixture");
} else {
  assert(!process.argv[2] || process.argv[2] === "--print", "Usage: semantic-oracle.mjs [--check|--print]");
  process.stdout.write(encoded);
}
