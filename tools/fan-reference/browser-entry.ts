import "@reference/dialogs/more-info/controls/more-info-fan";
import { ContextProvider } from "@lit/context";
import * as contexts from "@reference/data/context";
import { themeStyles } from "@reference/resources/theme/theme";
import { darkColorStyles } from "@reference/resources/theme/color/color.globals";
import { computeFormatFunctions } from "@reference/common/translations/entity-state";
import translations from "@reference/translations/en.json";
import base from "../../Tests/Fixtures/Fan/complete.json";
import variants from "../../Tests/Fixtures/Fan/render-variants.json";

// Synthetic state only. The real component/formatters run, but no HA connection exists.
const root = document.getElementById("fixture")!;
const style = document.createElement("style");
style.textContent = themeStyles + darkColorStyles.toString() + "body{margin:0;font-family:var(--ha-font-family-body);background:var(--card-background-color);color:var(--primary-text-color)}#fixture{box-sizing:border-box;padding:24px;height:620px;overflow:auto}more-info-fan{display:block}html{color-scheme:dark}";
document.head.append(style);
const localize = (key: string) => key.split(".").reduce((value: any, part) => value?.[part], translations) || "";
const locale = { language: "en", number_format: "language", time_format: "24", date_format: "language", time_zone: "server", first_weekday: "language" };
const calls: any[] = [];
const api = { callService: async (domain, service, data) => { calls.push({ domain, service, data }); }, callWS: async () => ({ resources: {} }), hassUrl: (path) => path, loadBackendTranslation: async () => localize };
const providers: any[] = [];
let component: any;
(window as any).harness = {
  calls, variants: Object.keys(variants),
  async setFixture(name = "complete", width = 520) {
    if (!(name in variants)) throw new Error("Unknown fake fixture: " + name);
    const variant = variants[name];
    const stateObj = { ...base, ...variant, attributes: { ...base.attributes, ...variant.attributes } };
    calls.length = 0;
    root.replaceChildren(); root.style.width = width + "px";
    const config = { unit_system: { temperature: "°C" }, time_zone: "UTC" };
    const formatters = await computeFormatFunctions(localize as any, locale as any, config as any, {}, {}, {}, {});
    const values = [[contexts.apiContext, api], [contexts.configContext, { config }], [contexts.internationalizationContext, { locale, localize, language: "en", loadBackendTranslation: async () => localize, loadFragmentTranslation: async () => localize }], [contexts.formattersContext, formatters], [contexts.entitiesContext, {}], [contexts.statesContext, { [stateObj.entity_id]: stateObj }], [contexts.uiContext, { themes: { darkMode: true }, selectedTheme: { dark: true } }]];
    if (!providers.length) for (const [context, initialValue] of values) providers.push(new ContextProvider(root, { context, initialValue }));
    else values.forEach(([, value], index) => providers[index].setValue(value));
    component = document.createElement("more-info-fan"); component.stateObj = stateObj; root.append(component);
    await component.updateComplete; await document.fonts.ready;
    return stateObj;
  },
  async replace(attributes = {}, state?: string) {
    component.stateObj = { ...component.stateObj, state: state ?? component.stateObj.state, attributes: { ...component.stateObj.attributes, ...attributes } };
    await component.updateComplete;
  },
};
(window as any).harnessReady = true;
(window as any).harness.setFixture();
