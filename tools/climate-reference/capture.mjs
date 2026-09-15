#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here,"../..");
const reference = "/Users/jin/Documents/HA/hass-frontend";
const requireReference = createRequire(path.join(reference,"package.json"));
const { chromium } = requireReference("playwright");
const output = path.join(root,".build/climate-reference");
const capture = JSON.parse(fs.readFileSync(path.join(root,"Tests/Fixtures/Climate/live-room-ac-capture.json"),"utf8"));
const fixtures = JSON.parse(fs.readFileSync(path.join(root,"Tests/Fixtures/Climate/render-states.json"),"utf8"));
const server = http.createServer((request,response)=>{
  const pathname = decodeURIComponent(new URL(request.url,"http://localhost").pathname);
  let file = path.join(output,pathname === "/" ? "index.html" : pathname);
  if (pathname.includes("Roboto-") && pathname.endsWith(".woff2")) file = path.join(reference,"node_modules/roboto-fontface/fonts/roboto",path.basename(pathname));
  if (!file.startsWith(output) && !file.includes("node_modules/roboto-fontface/")) {response.writeHead(403).end();return;}
  try {const content=fs.readFileSync(file);response.setHeader("Content-Type",file.endsWith(".js")?"text/javascript":file.endsWith(".json")?"application/json":file.endsWith(".woff2")?"font/woff2":"text/html");response.end(content);}catch{response.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"});
  const page = await browser.newPage({viewport:{width:600,height:720},deviceScaleFactor:2,colorScheme:"dark",locale:"en-US",timezoneId:"Asia/Shanghai"});
  const errors=[];page.on("pageerror",error=>{errors.push(String(error));console.error(String(error));});page.on("console",message=>{if(message.type()==="error")errors.push(message.text());});
  await page.route("**/*",route=>route.request().url().startsWith(origin)?route.continue():route.abort());
  await page.goto(origin);await page.waitForFunction(()=>window.harnessReady);
  const report = {browser:browser.version(),viewport:{width:600,height:720},scale:2,locale:"en-US",timezone:"Asia/Shanghai",renders:[],interactions:[]};
  const set = async (state,width=520)=>{await page.evaluate(({state,width})=>window.harness.setFixture(state,width),{state,width});await page.waitForTimeout(350);};
  const stateFor = variant=>({...fixtures.base,state:variant.state,attributes:variant.replaceAttributes?variant.attributes:{...fixtures.base.attributes,...variant.attributes},last_changed:fixtures.timestamp,last_updated:fixtures.timestamp});
  await set(capture.state);await page.locator("#fixture").screenshot({path:path.join(output,"live-off-520.png")});
  for(const variant of fixtures.variants) for(const width of [520,360]) {
    const state = stateFor(variant);errors.length=0;
    let setError;
    try {await set(state,width);}catch(error){setError=String(error);}
    const file = `reference-${variant.name}-${width}x620.png`;
    // Sparse missing hvac_modes is a known reference render error, not an approved blank baseline.
    if(!setError) await page.locator("#fixture").screenshot({path:path.join(output,file)});
    report.renders.push({name:variant.name,width,state,file:setError?null:file,setError,errors:[...errors],menus:await page.locator("ha-control-select-menu").count(),sliders:await page.locator("ha-control-circular-slider").count()});
  }
  const cool=stateFor(fixtures.variants.find(v=>v.name==="cooling"));
  for(const width of [520,360]) {
    const sparseValid={...stateFor(fixtures.variants.find(v=>v.name==="sparse")),attributes:{friendly_name:"Sparse climate",hvac_modes:[]}};
    errors.length=0;await set(sparseValid,width);const file=`reference-sparse-valid-${width}x620.png`;await page.locator("#fixture").screenshot({path:path.join(output,file)});
    report.renders.push({name:"sparse-valid",width,state:sparseValid,file,errors:[...errors],qualification:"Additional web-renderable sparse fixture; hvac_modes=[] differs from raw native sparse fixture"});
  }
  const offGrid={...cool,attributes:{...cool.attributes,temperature:22.25,target_temp_step:0.5}};
  for(const key of ["ArrowUp","ArrowDown","PageUp","PageDown","Home","End"]) {
    await set(offGrid);await page.locator('ha-control-circular-slider [role="slider"]').press(key);
    report.interactions.push({kind:"keyboard",key,start:22.25,step:0.5,calls:await page.evaluate(()=>window.harness.calls)});
  }
  await set(cool);await page.locator("ha-outlined-icon-button").nth(1).click();await page.waitForFunction(()=>window.harness.calls.length===1);
  report.interactions.push({kind:"plus",calls:await page.evaluate(()=>window.harness.calls)});
  await set(cool);
  const box=await page.locator("ha-control-circular-slider").boundingBox();
  await page.mouse.click(box.x+box.width/2,box.y+box.height*0.047);
  report.interactions.push({kind:"tap-top",calls:await page.evaluate(()=>window.harness.calls)});
  await set(cool);const dragBox=await page.locator("ha-control-circular-slider").boundingBox();
  await page.mouse.move(dragBox.x+dragBox.width*0.047,dragBox.y+dragBox.height/2);await page.mouse.down();await page.mouse.move(dragBox.x+dragBox.width/2,dragBox.y+dragBox.height*0.047,{steps:12});
  const intermediate=await page.evaluate(()=>window.harness.calls.slice());await page.mouse.up();
  report.interactions.push({kind:"drag-left-top",intermediate,calls:await page.evaluate(()=>window.harness.calls)});
  const complete=stateFor(fixtures.variants.find(v=>v.name==="complete"));await set(complete);
  await page.locator('ha-control-circular-slider [role="slider"]').nth(1).press("ArrowDown");
  report.interactions.push({kind:"range-high-key",calls:await page.evaluate(()=>window.harness.calls)});
  await set(complete);await page.locator("ha-icon-button-toggle").nth(1).click();await page.waitForTimeout(350);
  await page.locator("#fixture").screenshot({path:path.join(output,"reference-complete-humidity-520x620.png")});
  report.interactions.push({kind:"humidity-toggle",humidityControls:await page.locator("ha-state-control-climate-humidity").count(),calls:await page.evaluate(()=>window.harness.calls)});
  await page.locator("#fixture").evaluate(el=>el.style.width="360px");await page.waitForTimeout(350);
  await page.locator("#fixture").screenshot({path:path.join(output,"reference-complete-humidity-360x620.png")});
  await set(cool);await page.locator('ha-control-circular-slider [role="slider"]').press("Shift");
  await page.locator("#fixture").screenshot({path:path.join(output,"reference-cooling-keyboard-focus-520x620.png")});
  report.focus = await page.locator('ha-control-circular-slider [role="slider"]').evaluate(el=>({matchesFocus:el.matches(":focus"),matchesFocusVisible:el.matches(":focus-visible"),strokeWidth:getComputedStyle(el).strokeWidth}));
  for(const [index,value,kind] of [[0,"cool","hvac-menu"],[1,"sleep","preset-menu"],[2,"high","fan-menu"],[3,"vertical","swing-menu"],[4,"horizontal","horizontal-menu"]]) {
    await set(complete);const menu=page.locator("ha-control-select-menu").nth(index);await menu.locator("button").first().click();
    const options=menu.locator("ha-dropdown-item");const count=await options.count();let selected=false;
    for(let i=0;i<count;i++)if(await options.nth(i).evaluate(el=>el.value)===value){await options.nth(i).click();selected=true;break;}
    assert(selected,`Missing menu option ${value}`);report.interactions.push({kind,value,calls:await page.evaluate(()=>window.harness.calls)});
  }
  report.finalErrors=[...errors];
  for(const render of report.renders) {
    assert.equal(render.errors.length,0,`Runtime errors for ${render.name}`);
    if(render.name==="sparse") assert(render.setError?.includes("concat"),"Expected raw sparse reference failure changed");
    else assert(!render.setError,`Unexpected render failure ${render.name}`);
  }
  for(const interaction of report.interactions) {
    if(interaction.kind==="humidity-toggle") assert.equal(interaction.calls.length,0);
    else assert.equal(interaction.calls.length,1,`Service count ${interaction.kind}`);
    if(interaction.kind==="drag-left-top") assert.equal(interaction.intermediate.length,0);
  }
  fs.writeFileSync(path.join(output,"report.json"),JSON.stringify(report,null,2)+"\n");
  console.log(JSON.stringify(report.interactions,null,2));
  assert.equal(report.finalErrors.length,0,"Unexpected final runtime errors");
} finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
