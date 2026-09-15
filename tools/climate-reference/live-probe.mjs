#!/usr/bin/env node
// Read-only deployment evidence. Print JSON; never call a mutating HA endpoint.
import assert from "node:assert/strict";
import fs from "node:fs";

const endpoint = process.env.HA_BASE_URL || "http://joyj.me:8123";
const token = process.env.HA_TOKEN || fs.readFileSync("/Users/jin/Documents/Computer/ha_apikey.txt", "utf8").trim();
const paths = ["states/climate.room_ac", "config", "services"];
const [state, config, services] = await Promise.all(paths.map(async (path) => {
  const response = await fetch(`${endpoint}/api/${path}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(15000),
  });
  assert(response.ok, `${path}: HTTP ${response.status}`);
  return response.json();
}));
assert.equal(state.entity_id, "climate.room_ac");
const climateServices = services.find((entry) => entry.domain === "climate");
assert(climateServices, "Climate service metadata missing");
console.log(JSON.stringify({
  capturedAt: new Date().toISOString(),
  endpoint,
  requests: paths.map((path) => ({ method: "GET", path: `/api/${path}` })),
  state,
  config: { version: config.version, unit_system: config.unit_system, time_zone: config.time_zone, language: config.language },
  climateServices,
}, null, 2));
