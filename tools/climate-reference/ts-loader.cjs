const ts = require('/Users/jin/Documents/HA/hass-frontend/node_modules/typescript');
module.exports = function(source) {
  return ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, experimentalDecorators: true, useDefineForClassFields: false}}).outputText;
};
