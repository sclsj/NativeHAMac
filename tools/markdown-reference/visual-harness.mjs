#!/usr/bin/env node
// Offline component-style approximation, not the full HA runtime or a native golden.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const reference = "/Users/jin/Documents/HA/hass-frontend";
const args = process.argv.slice(2);
assert(
  args.length === 0 || (args.length === 2 && args[0] === "--capture"),
  "Usage: visual-harness.mjs [--capture /absolute/browser/executable]",
);
const out = path.join(here, "generated");
fs.mkdirSync(out, { recursive: true });
execFileSync(process.execPath, [path.join(here, "oracle.mjs"), "--check"], {
  stdio: "inherit",
});
const read = (p) => fs.readFileSync(path.join(reference, p), "utf8");
const hashes = {};
const css = (p, name = "static styles") => {
  const source = read(p);
  hashes[p] = createHash("sha256").update(source).digest("hex");
  const start = source.indexOf(name);
  assert(start >= 0, p);
  const match = source.slice(start).match(/css`([\s\S]*?)`/);
  assert(match && !match[1].includes("${"), `Nonliteral CSS ${p}`);
  return match[1];
};
const styles = {
  alert: css("src/components/ha-alert.ts"),
  svg: css("src/components/ha-svg-icon.ts"),
  markdown: css("src/components/ha-markdown.ts"),
  card: css("src/components/ha-card.ts"),
  wrapper: css("src/panels/lovelace/cards/hui-markdown-card.ts"),
};
const globals =
  css("src/resources/theme/typography.globals.ts", "typographyStyles") +
  css("src/resources/theme/core.globals.ts", "coreStyles") +
  css("src/resources/theme/color/color.globals.ts", "darkColorStyles");
let fonts = "";
for (const [name, weight, style] of [
  ["Regular", 400, "normal"],
  ["Bold", 700, "normal"],
  ["RegularItalic", 400, "italic"],
  ["BoldItalic", 700, "italic"],
]) {
  const p = `node_modules/roboto-fontface/fonts/roboto/Roboto-${name}.woff2`;
  const data = fs.readFileSync(path.join(reference, p));
  hashes[p] = createHash("sha256").update(data).digest("hex");
  fonts += `@font-face{font-family:Roboto;font-weight:${weight};font-style:${style};src:url(data:font/woff2;base64,${data.toString("base64")}) format('woff2')}\n`;
}
const expected = JSON.parse(
  fs.readFileSync(
    path.join(root, "Tests/Fixtures/Markdown/expected-worker.json"),
    "utf8",
  ),
);
const input = JSON.parse(
  fs.readFileSync(
    path.join(root, "Tests/Fixtures/Markdown/cases.json"),
    "utf8",
  ),
);
const coreSource = fs.readFileSync(path.join(here, "core.md"), "utf8");
// Use exact installed worker for the captured live result, not local template expansion.
const requireReference = createRequire(path.join(reference, "package.json"));
const ts = requireReference("typescript");
const xss = requireReference("xss");
const { marked } = await import(
  pathToFileURL(requireReference.resolve("marked")).href
);
const source = read("src/resources/markdown-worker.ts");
const adapted = source
  .replace(/^import .*;\n/gm, "")
  .replace("expose(api);", "return api;");
const compiled = ts.transpileModule(adapted, {
  compilerOptions: {
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.CommonJS,
  },
}).outputText;
const worker = new Function(
  "marked",
  "filterXSS",
  "getDefaultWhiteList",
  "exports",
  compiled,
)(marked, xss.filterXSS, xss.getDefaultWhiteList, {});
const livePath = path.join(
  root,
  "Tests/Fixtures/Markdown/live-template-capture.json",
);
assert(fs.existsSync(livePath), `Captured live report required: ${livePath}`);
const live = JSON.parse(fs.readFileSync(livePath, "utf8")).cards[0].event
  .result;
const liveHTML = (
  await worker.renderMarkdown(
    live,
    { breaks: true, gfm: true },
    { allowSvg: false, allowDataUrl: false },
  )
).join("");
const statusSource = fs
  .readFileSync(path.join(here, "status.md"), "utf8")
  .trimEnd();
const statusHTML = (
  await worker.renderMarkdown(
    statusSource,
  coreSource,
    { breaks: true, gfm: true },
    { allowSvg: false, allowDataUrl: false },
  )
).join("");
const mdi = requireReference("@mdi/js");
const icons = {
  info: mdi.mdiInformationOutline,
  warning: mdi.mdiAlertOutline,
  error: mdi.mdiAlertCircleOutline,
  success: mdi.mdiCheckboxMarkedCircleOutline,
};
const core = (await worker.renderMarkdown(coreSource,{breaks:true,gfm:true},{allowSvg:false,allowDataUrl:false})).join('');
const fixtureStates = [
  { id: "status", html: statusHTML },
  { id: "status-text-only", textOnly: true, html: statusHTML },
  { id: "pending", title: "Pending template", html: "" },
  {
    id: "error",
    title: "Template result retained",
    html: liveHTML,
    error: "TemplateError: fixture failure",
  },
  { id: "core", title: "Markdown reference", html: core },
  { id: "live-result", html: liveHTML },
  {
    id: "text-only",
    title: "Suppressed title",
    textOnly: true,
    html: liveHTML,
  },
  {
    id: "fallback-proposal",
    fallback: true,
    source: input.cases.find((r) => r.id === "custom-elements").source,
  },
];
const payload = JSON.stringify({ styles, fixtureStates, icons }).replaceAll(
  "<",
  "\\u003c",
);
const html = `<!doctype html><html lang="en"><meta charset="utf-8"><title>Component-style approximation — Module 08</title>
<style>${globals}${fonts}
html{--info-color:#039be5;--warning-color:#ffa600;--error-color:#db4437;--success-color:#43a047;--primary-color:#009ac7;color-scheme:dark}body{margin:24px;background:#111;color:#e1e1e1;font:14px/1.6 Roboto,Noto,sans-serif;-webkit-font-smoothing:antialiased}h1{font-size:20px}section{margin:24px 0}p.label{font:12px/1.4 monospace;color:#aaa}hui-markdown-card{display:block}pre.fallback{white-space:pre-wrap;overflow-wrap:anywhere;margin:0;padding:16px;border:1px dashed #777;font:12px/1.4 monospace}
</style><h1>Component-style reference approximation</h1><p>Exact worker output and extracted component CSS. Static shadow DOM; not live HA. Fallback proposal is a NativeHA staging aid, not reference behavior.</p><main></main>
<script>const data=${payload};
// Static alert DOM/CSS approximation of ha-alert; no dismiss or custom slots.
function makeAlert(type){
 const alert=document.createElement('ha-alert');const shadow=alert.attachShadow({mode:'open'});const style=document.createElement('style');style.textContent=data.styles.alert;shadow.append(style);
 const issue=document.createElement('div');issue.className='issue-type '+type;issue.setAttribute('role','alert');shadow.append(issue);
 const icon=document.createElement('div');icon.className='icon no-title';issue.append(icon);const svgHost=document.createElement('ha-svg-icon');icon.append(svgHost);const svgRoot=svgHost.attachShadow({mode:'open'});svgRoot.innerHTML='<style>'+data.styles.svg+'</style><svg viewBox="0 0 24 24" preserveAspectRatio="xMidYMid meet" focusable="false" role="img" aria-hidden="true"><g><path class="primary-path" d="'+data.icons[type]+'"></path></g></svg>';
 const content=document.createElement('div');content.className='content';issue.append(content);const main=document.createElement('div');main.className='main-content';main.append(document.createElement('slot'));content.append(main);const action=document.createElement('div');action.className='action';content.append(action);return alert;
}
function convertAlerts(content){
 for(const quote of content.querySelectorAll('blockquote')){
  const first=quote.firstElementChild?.firstChild;
  const match=first?.textContent&&/(?<input>(\\[!(?<type>caution|important|note|tip|warning)\\])(?:\\s|\\\\n)?)/i.exec(first.textContent);
  if(!match)continue;
  const type={caution:'error',important:'info',note:'info',tip:'success',warning:'warning'}[match.groups.type.toLowerCase()];
  const alert=makeAlert(type);
  alert.append(...Array.from(quote.childNodes).flatMap(child=>Array.from(child.childNodes)).filter(child=>child.textContent&&child.textContent!==match.input));
  quote.replaceWith(alert);
 }
}

for(const width of [496,320])for(const fixture of data.fixtureStates){
 const section=document.createElement('section');const label=document.createElement('p');label.className='label';label.textContent=fixture.id+' / '+width+' CSS px / approximation';section.append(label);
 const wrapper=document.createElement('hui-markdown-card');wrapper.id=fixture.id+'-'+width;wrapper.style.width=width+'px';section.append(wrapper);document.querySelector('main').append(section);
 const root=wrapper.attachShadow({mode:'open'});const style=document.createElement('style');style.textContent=data.styles.wrapper;root.append(style);
 if(fixture.fallback){const pre=document.createElement('pre');pre.textContent=fixture.source;pre.style.cssText='white-space:pre-wrap;overflow-wrap:anywhere;margin:0;padding:16px;border:1px dashed #777;font:12px/1.4 monospace';root.append(pre);continue;}
 if(fixture.error){const alert=makeAlert('error');alert.textContent=fixture.error;root.append(alert);}
 const card=document.createElement('ha-card');if(fixture.title)card.classList.add('with-header');if(fixture.textOnly)card.classList.add('text-only');root.append(card);
 const cardRoot=card.attachShadow({mode:'open'});const cardStyle=document.createElement('style');cardStyle.textContent=data.styles.card;cardRoot.append(cardStyle);
 if(fixture.title&&!fixture.textOnly){const header=document.createElement('h1');header.className='card-header';header.textContent=fixture.title;cardRoot.append(header);}cardRoot.append(document.createElement('slot'));
 const markdown=document.createElement('ha-markdown');card.append(markdown);const markdownRoot=markdown.attachShadow({mode:'open'});const mdStyle=document.createElement('style');mdStyle.textContent=data.styles.markdown;markdownRoot.append(mdStyle);const content=document.createElement('ha-markdown-element');content.innerHTML=fixture.html;markdownRoot.append(content);convertAlerts(content);
}
window.harnessReady=document.fonts.ready.then(()=>true);
</script></html>`;
fs.writeFileSync(path.join(out, "index.html"), html);
const metadata = {
  kind: "component-style-reference-approximation",
  referenceRevision: expected.revision,
  cssAndFontHashes: hashes,
  workerSourceHashes: expected.sourceHashes,
  widths: [496, 320],
  states: fixtureStates.map(({ id }) => id),
  liveResult: live,
  statusSource,
  coreSource,
  limitations: [
    "Static manually assembled shadow DOM; no Lit/component runtime",
    "No template lifecycle, actions or image loading; alert marker conversion and static alert DOM approximated",
    "Dark defaults only; no live custom theme",
    "Fallback is proposed NativeHA staging presentation, not hass-frontend parity",
    "Not an approved native visual golden",
  ],
};
fs.writeFileSync(
  path.join(out, "metadata.json"),
  JSON.stringify(metadata, null, 2) + "\n",
);
console.log(
  `Generated ${path.join(out, "index.html")}; no browser launched unless --capture supplied.`,
);
if (args[0] === "--capture") {
  const { chromium } = requireReference("playwright");
  const browser = await chromium.launch({
    headless: true,
    executablePath: args[1],
  });
  try {
    const context = await browser.newContext({
      viewport: { width: 900, height: 900 },
      deviceScaleFactor: 2,
      colorScheme: "dark",
      reducedMotion: "reduce",
      locale: "en-US",
      timezoneId: "America/New_York",
    });
    await context.route("**/*", (route) =>
      route.request().url().startsWith("file:")
        ? route.continue()
        : route.abort(),
    );
    const page = await context.newPage();
    await page.goto(pathToFileURL(path.join(out, "index.html")).href);
    await page.evaluate(() => window.harnessReady);
    for (const width of [496, 320])
      for (const fixture of fixtureStates)
        await page
          .locator("#" + fixture.id + "-" + width)
          .screenshot({
            path: path.join(out, fixture.id + "-" + width + ".png"),
            animations: "disabled",
          });
  } finally {
    await browser.close();
  }
}
