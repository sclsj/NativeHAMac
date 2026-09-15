#!/usr/bin/env node
// Execute selected exact reference TS methods; no browser, network, or app code.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const reference = process.env.HA_REFERENCE_ROOT || "/Users/jin/Documents/HA/hass-frontend";
const requireReference = createRequire(path.join(reference, "package.json"));
const ts = requireReference("typescript");
const sources = {};
const extractions = {};
function read(relative) {
  const source = fs.readFileSync(path.join(reference, relative), "utf8");
  sources[relative] = createHash("sha256").update(source).digest("hex");
  return ts.createSourceFile(relative, source, ts.ScriptTarget.Latest, true);
}
function evaluate(source, bindings, exportNames) {
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  return new Function(...Object.keys(bindings), "exports", compiled + `\nreturn {${exportNames.join(",")}};`)(...Object.values(bindings), {});
}
function moduleSource(file) {
  const parsed = read(file);
  return parsed.statements.filter((node) => !ts.isImportDeclaration(node)).map((node) => node.getText(parsed).replace(/^export /, "")).join("\n");
}
function selectedClass(file, className, topNames, memberNames, bindings) {
  const parsed = read(file);
  const declaration = parsed.statements.find((node) => ts.isClassDeclaration(node) && node.name?.text === className);
  assert(declaration, `Missing class ${className}`);
  const top = topNames.map((name) => {
    const matches = parsed.statements.filter((node) => node.name?.text === name || (ts.isVariableStatement(node) && node.declarationList.declarations.some((item) => item.name.getText(parsed) === name)));
    assert.equal(matches.length, 1, `Top-level extraction ${name}`);
    return matches[0].getText(parsed);
  });
  const members = memberNames.map((name) => {
    const matches = declaration.members.filter((node) => node.name?.getText(parsed) === name);
    assert.equal(matches.length, 1, `Member extraction ${name}`);
    // Selected members must be undecorated methods/getters or arrow properties.
    assert(!(ts.getDecorators?.(matches[0]) || []).length, `Unexpected decorator ${name}`);
    return matches[0].getText(parsed);
  });
  extractions[file] = { className, topNames, memberNames };
  return evaluate(`${top.join("\n")}\nclass ${className} {\n${members.join("\n")}\n}`, bindings, [className])[className];
}

const { clamp } = evaluate(moduleSource("src/common/number/clamp.ts"), {}, ["clamp"]);
const { supportsFeature, supportsFeatureFromAttributes } = evaluate(moduleSource("src/common/entity/supports-feature.ts"), {}, ["supportsFeature", "supportsFeatureFromAttributes"]);
const climate = evaluate(moduleSource("src/data/climate.ts"), requireReference("@mdi/js"), ["HVAC_MODES", "ClimateEntityFeature", "compareClimateHvacModes", "CLIMATE_HVAC_ACTION_TO_MODE"]);
const sliderMethods = ["_valueToPercentage", "_percentageToValue", "_steppedValue", "_boundedValue", "_getPercentageFromEvent", "_findActiveSlider", "_setActiveValue", "_getActiveValue", "_tenPercentStep", "_handleKeyDown", "_handleKeyUp", "_strokeDashArc"];
const CircularSlider = selectedClass("src/components/ha-control-circular-slider.ts", "HaControlCircularSlider", ["MAX_ANGLE", "ROTATE_ANGLE", "RADIUS", "xy2polar", "rad2deg", "A11Y_KEY_CODES"], sliderMethods, { clamp, fireEvent: (owner, type, detail) => owner.events.push({ type, ...detail }) });
const Temperature = selectedClass("src/state-control/climate/ha-state-control-climate-temperature.ts", "HaStateControlClimateTemperature", [], ["_step", "_min", "_max", "_valueChanged", "_valueChanging", "_callService", "_handleButton", "_supportsTargetTemperature", "_supportsTargetTemperatureRange"], { clamp, supportsFeature, ClimateEntityFeature: climate.ClimateEntityFeature, UNIT_F: "°F" });
function slider(overrides = {}) {
  return Object.assign(new CircularSlider(), { min: 19, max: 28, step: 0.1, dual: false, _localValue: 22.8, _activeSlider: "value", events: [], _slider: { getBoundingClientRect: () => ({ left: 0, top: 0, width: 320, height: 320 }) } }, overrides);
}
function temperature(attributes = {}, overrides = {}) {
  const entityAttributes = { min_temp: 19, max_temp: 28, target_temp_step: 0.1, supported_features: 1, temperature: 22.8, ...attributes };
  const target = { value: entityAttributes.temperature, low: entityAttributes.target_temp_low, high: entityAttributes.target_temp_high };
  const control = Object.assign(new Temperature(), { stateObj: { entity_id: "climate.fixture", state: "cool", attributes: entityAttributes }, _config: { config: { unit_system: { temperature: "°C" } } }, _targetTemperature: target, calls: [], scheduled: [], ...overrides });
  control._api = { callService: (domain, service, data) => control.calls.push({ domain, service, data }) };
  // Record scheduling requests only; no fake timing claim for the omitted debounce runtime.
  control._debouncedCallService = (target) => control.scheduled.push(target);
  return control;
}
const mapping = [["bottom-left", 0, 320], ["left", 0, 160], ["top", 160, 0], ["right", 320, 160], ["bottom-right", 320, 320], ["gap-left", 159.999, 320], ["gap-right", 160.001, 320], ["gap-center", 160, 320], ["center", 160, 160]].map(([id, x, y]) => {
  const s = slider(); const percentage = s._getPercentageFromEvent({ center: { x, y } }); const raw = s._percentageToValue(percentage);
  return { id, point: { x, y }, percentage, raw, bounded: s._boundedValue(raw), stepped: s._steppedValue(s._boundedValue(raw)) };
});
const roundingInputs = [["celsius-half", 19, 28, 0.5, 22.25], ["negative-half", -10, 10, 0.5, -1.25], ["non-grid-min", 19.2, 28.2, 0.5, 19.2], ["non-grid-max", 19.2, 28.2, 0.5, 28.2], ["over-max", 19, 28, 0.1, 99], ["below-min", 19, 28, 0.1, 0], ["fahrenheit-half", 50, 90, 1, 72.5], ["zero-step", 19, 28, 0, 22], ["negative-step", 19, 28, -0.5, 22.25]];
const rounding = roundingInputs.map(([id, min, max, step, input]) => { const s = slider({ min, max, step }); const bounded = s._boundedValue(input); return { id, min, max, step, input, bounded, stepped: s._steppedValue(bounded), percentage: s._valueToPercentage(input) }; });
const dual = [17, 20, 22, 24, 29].map((input) => { const s = slider({ dual: true, _localLow: 20, _localHigh: 24 }); s._activeSlider = s._findActiveSlider(input); return { input, active: s._activeSlider, bounded: s._boundedValue(input) }; });
const dualOffGrid = [["low", 20, 23.8, 24], ["high", 20.2, 24, 19]].map(([active, low, high, input]) => { const s = slider({ dual: true, step: 0.5, _localLow: low, _localHigh: high, _activeSlider: active }); const bounded = s._boundedValue(input); return { active, low, high, input, step: s.step, bounded, stepped: s._steppedValue(bounded) }; });
const keyboard = ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].map((code) => { const s = slider(); const event = { code, currentTarget: { id: "value" }, preventDefault() {} }; s._handleKeyDown(event); s._handleKeyUp(event); return { code, value: s._localValue, events: s.events }; });
const buttonInputs = [["off-grid-add", { temperature: 22.25, target_temp_step: 0.5 }, "value", 0.5], ["upper-clamp", { temperature: 28 }, "value", 0.1], ["lower-clamp", { temperature: 19 }, "value", -0.1], ["missing-single", { temperature: null }, "value", 0.1], ["range-low-cross", { target_temp_low: 23.9, target_temp_high: 24 }, "low", 1], ["range-high-cross", { target_temp_low: 20, target_temp_high: 20.1 }, "high", -1]];
const buttons = buttonInputs.map(([id, attributes, target, step]) => { const c = temperature(attributes); c._handleButton({ currentTarget: { target, step } }); c._callService(target); return { id, attributes, target, step, targets: c._targetTemperature, scheduled: c.scheduled, calls: c.calls }; });
const capabilityInputs = [{ supported_features: 0 }, { supported_features: 1, temperature: null }, { supported_features: 1, temperature: 0 }, { supported_features: 2, temperature: null, target_temp_low: 20, target_temp_high: 24 }, { supported_features: 3, temperature: 22, target_temp_low: 20, target_temp_high: 24 }, { supported_features: 2, target_temp_low: 20, target_temp_high: null }];
const capabilities = capabilityInputs.map((attributes) => { const c = temperature(attributes); return { attributes, single: c._supportsTargetTemperature, range: c._supportsTargetTemperatureRange }; });
const stepDefaults = [undefined, 0, 0.1, -0.5].flatMap((input) => ["°C", "°F"].map((unit) => { const c = temperature({ target_temp_step: input }); c._config.config.unit_system.temperature = unit; return { input, unit, step: c._step }; }));
const valueEvents = ["value-changing", "value-changed", "low-changed", "high-changed"].map((type) => { const c = temperature({ supported_features: 3, target_temp_low: 20, target_temp_high: 24 }); const event = { type, detail: { value: 22 } }; (type.endsWith("-changing") ? c._valueChanging.bind(c) : c._valueChanged.bind(c))(event); return { type, targets: c._targetTemperature, calls: c.calls }; });
const output = { referenceRevision: execFileSync("git", ["-C", reference, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(), typescriptVersion: ts.version, sources, extractions, hvacModes: [...climate.HVAC_MODES].reverse().sort(climate.compareClimateHvacModes), featureBits: Object.fromEntries(Object.entries(climate.ClimateEntityFeature).filter(([name]) => Number.isNaN(Number(name)))), actionModes: climate.CLIMATE_HVAC_ACTION_TO_MODE, featureMasks: [undefined, 0, 1, 2, 16, 401, 512].map((mask) => ({ mask, target: supportsFeatureFromAttributes({ supported_features: mask }, 1), preset: supportsFeatureFromAttributes({ supported_features: mask }, 16), horizontal: supportsFeatureFromAttributes({ supported_features: mask }, 512) })), mapping, rounding, dual, keyboard, buttons, capabilities, stepDefaults, valueEvents };
output.dualOffGrid = dualOffGrid;
const encoded = JSON.stringify(output, (_key, value) => value === undefined ? { $undefined: true } : typeof value === "number" && !Number.isFinite(value) ? { $number: String(value) } : Object.is(value, -0) ? { $number: "-0" } : value, 2) + "\n";
if (process.argv[2] === "--check") {
  assert.equal(encoded, fs.readFileSync(path.join(root, "Tests/Fixtures/Climate/expected-semantics.json"), "utf8"), "Reference semantic output/source provenance changed");
  console.log("Climate semantic reference matches checked fixture");
} else {
  assert(!process.argv[2] || process.argv[2] === "--print", "Usage: semantic-oracle.mjs [--check|--print]");
  process.stdout.write(encoded);
}
