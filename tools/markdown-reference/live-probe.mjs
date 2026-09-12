#!/usr/bin/env node
// Read-only deployment evidence: config, current user, templates, unsubscribe.
import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
const requireReference = createRequire(
  "/Users/jin/Documents/HA/hass-frontend/package.json",
);
const WebSocket = requireReference("ws");
const output = process.argv[2];
assert(
  output,
  "Usage: node tools/markdown-reference/live-probe.mjs /path/to/report.json",
);
const endpoint = "http://joyj.me:8123";
const ws = new WebSocket(endpoint.replace("http:", "ws:") + "/api/websocket");
const report = {
  capturedAt: new Date().toISOString(),
  endpoint,
  views: [],
  cards: [],
};
const pending = new Map();
let nextID = 1;
let remaining = 0;
let finished = false;
const timer = setTimeout(
  () => fail(new Error("Read-only probe timed out")),
  20000,
);
function fail(error) {
  if (finished) return;
  finished = true;
  clearTimeout(timer);
  console.error(error.message);
  process.exitCode = 1;
  ws.terminate();
}
function finish() {
  if (finished) return;
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  finished = true;
  clearTimeout(timer);
  console.log(
    `Captured ${report.cards.length} template results and acknowledged cleanup: ${output}`,
  );
  ws.close();
}
function command(message) {
  return new Promise((resolve, reject) => {
    const id = nextID++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, ...message }));
  });
}
async function start() {
  const [config, user] = await Promise.all([
    command({ type: "lovelace/config" }),
    command({ type: "auth/current_user" }),
  ]);
  assert.equal(typeof user.name, "string", "Current user name missing");
  report.views = config.views.map((view, index) => ({
    index,
    title: view.title,
    path: view.path,
  }));
  const walk = (value, path, view) => {
    if (!value || typeof value !== "object") return;
    if (value.type === "markdown")
      report.cards.push({ path, view, config: value });
    for (const [key, child] of Object.entries(value))
      walk(child, `${path}.${key}`, view);
  };
  config.views.forEach((view, index) =>
    walk(view, `views.${index}`, report.views[index]),
  );
  remaining = report.cards.length;
  if (!remaining) {
    finish();
    return;
  }
  for (const card of report.cards) {
    card.subscriptionID = nextID++;
    card.request = {
      id: card.subscriptionID,
      type: "render_template",
      template: card.config.content,
      variables: { config: card.config, user: user.name },
      strict: true,
      report_errors: false,
    };
    if (card.config.entity_id !== undefined)
      card.request.entity_ids = card.config.entity_id;
    pending.set(card.subscriptionID, {
      resolve: () => {
        card.acknowledged = true;
      },
      reject: fail,
    });
    ws.send(JSON.stringify(card.request));
  }
}
ws.on("message", async (data) => {
  try {
    const message = JSON.parse(data);
    if (message.type === "auth_required") {
      ws.send(
        JSON.stringify({
          type: "auth",
          access_token: fs
            .readFileSync("/Users/jin/Documents/Computer/ha_apikey.txt", "utf8")
            .trim(),
        }),
      );
    } else if (message.type === "auth_invalid") {
      fail(new Error("Home Assistant authentication rejected"));
    } else if (message.type === "auth_ok") {
      await start();
    } else if (message.type === "result") {
      const request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id);
      if (message.success) request.resolve(message.result);
      else request.reject(new Error(JSON.stringify(message.error)));
    } else if (message.type === "event") {
      const card = report.cards.find(
        (value) => value.subscriptionID === message.id,
      );
      if (!card || card.event) return;
      assert.equal(
        typeof message.event.result,
        "string",
        "Template did not produce a successful result",
      );
      card.event = message.event;
      await command({ type: "unsubscribe_events", subscription: message.id });
      card.unsubscribeAcknowledged = true;
      if (--remaining === 0) finish();
    }
  } catch (error) {
    fail(error);
  }
});
ws.on("error", fail);
ws.on("close", () => {
  if (!finished) fail(new Error("Socket closed before probe completed"));
});
