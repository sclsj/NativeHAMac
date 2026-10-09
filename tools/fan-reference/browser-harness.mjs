#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const reference = "/Users/jin/Documents/HA/hass-frontend";
const requireReference = createRequire(path.join(reference, "package.json"));
const { rspack } = requireReference("@rspack/core");
const output = path.resolve(here, "../../.build/fan-reference");
fs.mkdirSync(output, { recursive: true });
const aliases = Object.fromEntries(["static-html", "decorators", "directive", "directives/until", "directives/ref", "directives/class-map", "directives/style-map", "directives/if-defined", "directives/guard", "directives/cache", "directives/join", "directives/repeat", "directives/live", "directives/keyed", "polyfill-support"].map(name => [`lit/${name}$`, `lit/${name}.js`]));
aliases["@lit-labs/observers/resize-controller"] = "@lit-labs/observers/resize-controller.js";
const iconMetadataPath = path.join(output, "iconMetadata.json");
const icons = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(reference, "node_modules/@mdi/svg/meta.json"), "utf8")).map(icon => [icon.name, fs.readFileSync(path.join(reference, "node_modules/@mdi/svg/svg", icon.name + ".svg"), "utf8").match(/ d="([^"]+)"/)[1]]));
fs.mkdirSync(path.join(output, "static/mdi"), { recursive: true });
fs.writeFileSync(path.join(output, "static/mdi/fixture.json"), JSON.stringify(icons));
fs.writeFileSync(iconMetadataPath, JSON.stringify({ version: "7.4.47", parts: [{ file: "fixture" }] }));
aliases["../../build/mdi/iconMetadata.json"] = iconMetadataPath;
const compiler = rspack({ mode: "development", context: here, entry: path.join(here, "browser-entry.ts"), output: { path: output, filename: "bundle.js", publicPath: "/" }, devtool: false, resolve: { extensions: [".ts", ".js", ".json"], alias: { ...aliases, "@reference": path.join(reference, "src") }, modules: [path.join(reference, "node_modules"), "node_modules"] }, module: { rules: [{ test: /\.ts$/, exclude: /node_modules/, use: [path.resolve(here, "../climate-reference/ts-loader.cjs")] }, { test: /\.(woff2?|ttf|svg)$/, type: "asset/resource" }, { test: /\.css$/, type: "asset/source" }] }, plugins: [new rspack.DefinePlugin({ __DEV__: true, __DEMO__: true, __BACKWARDS_COMPAT__: false, __STATIC_PATH__: JSON.stringify("/static/"), __BUILD__: JSON.stringify("fan-reference"), __VERSION__: JSON.stringify("fixture") })] });
await new Promise((resolve, reject) => compiler.run((error, stats) => error ? reject(error) : stats.hasErrors() ? reject(new Error(stats.toString({ all: false, errors: true }))) : resolve()));
await new Promise(resolve => compiler.close(resolve));
fs.writeFileSync(path.join(output, "index.html"), '<!doctype html><html lang="en"><meta charset="utf-8"><div id="fixture"></div><script src="/bundle.js"></script></html>');
console.log(output);
if (process.argv.includes("--serve")) {
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    let file = path.resolve(output, "." + (pathname === "/" ? "/index.html" : pathname));
    const isFont = /\/Roboto-[^/]+\.woff2$/.test(pathname);
    if (isFont) file = path.join(reference, "node_modules/roboto-fontface/fonts/roboto", path.basename(pathname));
    if (!isFont && !file.startsWith(output + path.sep)) { response.writeHead(403).end(); return; }
    response.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'");
    try {
      const content = fs.readFileSync(file);
      response.setHeader("Content-Type", file.endsWith(".js") ? "text/javascript" : file.endsWith(".json") ? "application/json" : file.endsWith(".woff2") ? "font/woff2" : "text/html");
      response.end(content);
    } catch { response.writeHead(404).end(); }
  });
  server.listen(0, "127.0.0.1", () => console.log(`Fixture URL: http://127.0.0.1:${server.address().port}`));
  process.on("SIGTERM", () => server.close()); process.on("SIGINT", () => server.close());
}
