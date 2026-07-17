#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const TOOL_VERSION = "1.0.0";
const TOOL_PATH = fileURLToPath(import.meta.url);
const DEFAULT_REFERENCE_ROOT = "/Users/jin/Documents/HA/hass-frontend";

function usage(exitCode = 0) {
  const output = `Usage:
  node tools/reference-context/trace-ts-deps.mjs \\
    --manifest docs/reference-context/manifests/module-02.inputs.json \\
    [--reference-root /path/to/hass-frontend] \\
    [--out-json path] [--out-markdown path]

Options:
  --manifest PATH          Module seed manifest (recommended).
  --entry PATH[#SYMBOL]    Additional seed; repeatable.
  --reference-root PATH    Defaults to HASS_FRONTEND_ROOT or the local known path.
  --follow-package NAME    Traverse an allowlisted node_modules package; repeatable.
  --follow-type-only       Traverse type-only edges. They are always recorded.
  --max-depth N            Default 6.
  --max-nodes N            Default 5000.
  --out-json PATH          Write the canonical graph JSON.
  --out-markdown PATH      Write a compact human-readable graph summary.
  --help                   Show this help.

An entry symbol limits the seed file to the named top-level declaration and its
same-file declaration closure. Package/runtime behavior reached only through a
TypeScript type still needs an explicit runtime seed in the manifest.
`;
  (exitCode === 0 ? process.stdout : process.stderr).write(output);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = {
    referenceRoot: process.env.HASS_FRONTEND_ROOT || DEFAULT_REFERENCE_ROOT,
    entries: [],
    followPackages: [],
    followTypeOnly: false,
    maxDepth: 6,
    maxNodes: 5000,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const take = () => {
      const value = argv[++index];
      if (!value) usage(2);
      return value;
    };
    if (arg === "--help") usage(0);
    else if (arg === "--manifest") options.manifest = take();
    else if (arg === "--reference-root") options.referenceRoot = take();
    else if (arg === "--entry") options.entries.push(parseEntry(take()));
    else if (arg === "--follow-package") options.followPackages.push(take());
    else if (arg === "--follow-type-only") options.followTypeOnly = true;
    else if (arg === "--max-depth") options.maxDepth = Number.parseInt(take(), 10);
    else if (arg === "--max-nodes") options.maxNodes = Number.parseInt(take(), 10);
    else if (arg === "--out-json") options.outJson = take();
    else if (arg === "--out-markdown") options.outMarkdown = take();
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Number.isInteger(options.maxDepth) || options.maxDepth < 0) {
    throw new Error("--max-depth must be a non-negative integer");
  }
  if (!Number.isInteger(options.maxNodes) || options.maxNodes < 1) {
    throw new Error("--max-nodes must be a positive integer");
  }
  return options;
}

function parseEntry(value) {
  const hashIndex = value.lastIndexOf("#");
  if (hashIndex === -1) return { path: value, symbols: [] };
  return {
    path: value.slice(0, hashIndex),
    symbols: value
      .slice(hashIndex + 1)
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
  };
}

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])])
    );
  }
  return value;
}

function canonicalJSON(value) {
  return `${JSON.stringify(canonicalize(value), null, 2)}\n`;
}

function fingerprintPayload(graph) {
  const payload = structuredClone(graph);
  delete payload.graphFingerprint;
  delete payload.reference.root;
  delete payload.reference.gitHead;
  delete payload.reference.gitBranch;
  delete payload.reference.dirty;
  delete payload.nativeha.gitHead;
  delete payload.nativeha.gitBranch;
  delete payload.nativeha.dirty;
  for (const node of payload.nodes) {
    delete node.headBlob;
    delete node.worktreeBlob;
    delete node.dirty;
  }
  for (const anchor of payload.nativeha.anchors) {
    delete anchor.headBlob;
    delete anchor.worktreeBlob;
    delete anchor.dirty;
  }
  return payload;
}

function runGit(root, args, fallback = null) {
  try {
    return execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return fallback;
  }
}

function toPosix(path) {
  return path.split(sep).join("/");
}

function isWithin(root, path) {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function loadManifest(options, nativeRoot) {
  if (!options.manifest) return { data: {}, path: null, sha256: null };
  const path = resolve(nativeRoot, options.manifest);
  const data = readJSON(path);
  return { data, path, sha256: sha256(readFileSync(path)) };
}

function mergeOptions(options, manifest) {
  const data = manifest.data;
  const manifestEntries = (data.entries || []).map((entry) =>
    typeof entry === "string" ? parseEntry(entry) : { path: entry.path, symbols: entry.symbols || [] }
  );
  return {
    ...options,
    entries: [...manifestEntries, ...options.entries],
    followPackages: [...new Set([...(data.followPackages || []), ...options.followPackages])],
    followTypeOnly: options.followTypeOnly || Boolean(data.followTypeOnly),
    maxDepth: options.maxDepth === 6 && data.maxDepth != null ? data.maxDepth : options.maxDepth,
    maxNodes: options.maxNodes === 5000 && data.maxNodes != null ? data.maxNodes : options.maxNodes,
  };
}

function packageNameFromSpecifier(specifier) {
  if (specifier.startsWith(".") || specifier.startsWith("/") || specifier.startsWith("#")) return null;
  const parts = specifier.split("/");
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0];
}

function packageNameFromPath(referenceRoot, filePath) {
  const marker = `${sep}node_modules${sep}`;
  const index = filePath.lastIndexOf(marker);
  if (index === -1) return null;
  const rest = filePath.slice(index + marker.length).split(sep);
  return rest[0].startsWith("@") ? rest.slice(0, 2).join("/") : rest[0];
}

function packageRoot(referenceRoot, packageName) {
  return join(referenceRoot, "node_modules", ...packageName.split("/"));
}

function selectExportTarget(exportsValue, subpath) {
  if (typeof exportsValue === "string") return exportsValue;
  if (Array.isArray(exportsValue)) {
    for (const item of exportsValue) {
      const found = selectExportTarget(item, subpath);
      if (found) return found;
    }
    return null;
  }
  if (!exportsValue || typeof exportsValue !== "object") return null;
  const keys = Object.keys(exportsValue);
  if (keys.some((key) => key.startsWith("."))) {
    const exact = exportsValue[subpath];
    if (exact) return selectExportTarget(exact, subpath);
    for (const key of keys) {
      if (!key.includes("*")) continue;
      const [prefix, suffix] = key.split("*");
      if (!subpath.startsWith(prefix) || !subpath.endsWith(suffix || "")) continue;
      const wildcard = subpath.slice(prefix.length, subpath.length - (suffix || "").length);
      const selected = selectExportTarget(exportsValue[key], subpath);
      return selected?.replace("*", wildcard) || null;
    }
    return null;
  }
  for (const condition of ["import", "browser", "node", "default", "require"]) {
    if (exportsValue[condition] != null) {
      const found = selectExportTarget(exportsValue[condition], subpath);
      if (found) return found;
    }
  }
  return null;
}

function withRuntimeExtension(path) {
  if (existsSync(path) && statSync(path).isFile()) return path;
  for (const suffix of [".js", ".mjs", ".cjs", ".json", "/index.js", "/index.mjs", "/index.cjs"]) {
    const candidate = `${path}${suffix}`;
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  }
  return null;
}

function resolvePackageRuntime(referenceRoot, specifier) {
  const packageName = packageNameFromSpecifier(specifier);
  if (!packageName) return null;
  const root = packageRoot(referenceRoot, packageName);
  const packageJSONPath = join(root, "package.json");
  if (!existsSync(packageJSONPath)) return null;
  const packageJSON = readJSON(packageJSONPath);
  const remainder = specifier.slice(packageName.length);
  const subpath = remainder ? `.${remainder}` : ".";
  let target = selectExportTarget(packageJSON.exports, subpath);
  if (!target && subpath === ".") target = packageJSON.module || packageJSON.main;
  if (!target && subpath !== ".") target = remainder.slice(1);
  if (!target) return null;
  return withRuntimeExtension(resolve(root, target));
}

function yarnLocator(lockText, packageName, version) {
  const lines = lockText.split(/\r?\n/);
  const escapedName = packageName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const headerPattern = new RegExp(`^\"?${escapedName}@[^\"]*\"?:\\s*$`);
  for (let index = 0; index < lines.length; index += 1) {
    if (!headerPattern.test(lines[index])) continue;
    const block = [lines[index]];
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      if (lines[cursor] && !/^\s/.test(lines[cursor])) break;
      block.push(lines[cursor]);
    }
    const joined = block.join("\n");
    if (!joined.includes(`version: ${version}`) && !joined.includes(`version: \"${version}\"`)) continue;
    return {
      key: lines[index].replace(/:\s*$/, "").replace(/^\"|\"$/g, ""),
      checksum: joined.match(/^\s+checksum:\s+(.+)$/m)?.[1]?.replace(/^\"|\"$/g, "") || null,
    };
  }
  return null;
}

function packageMetadata(referenceRoot, packageName, lockInfo, cache) {
  if (cache.has(packageName)) return cache.get(packageName);
  const root = packageRoot(referenceRoot, packageName);
  const packageJSONPath = join(root, "package.json");
  if (!existsSync(packageJSONPath)) return null;
  const bytes = readFileSync(packageJSONPath);
  const packageJSON = JSON.parse(bytes.toString("utf8"));
  const metadata = {
    name: packageJSON.name || packageName,
    version: packageJSON.version || "unknown",
    packageJSONSha256: sha256(bytes),
    lock: lockInfo.text ? yarnLocator(lockInfo.text, packageName, packageJSON.version) : null,
  };
  cache.set(packageName, metadata);
  return metadata;
}

function fileIdentity(referenceRoot, filePath, packageCache, lockInfo) {
  const content = readFileSync(filePath);
  const rel = toPosix(relative(referenceRoot, filePath));
  const packageName = packageNameFromPath(referenceRoot, filePath);
  if (packageName) {
    const metadata = packageMetadata(referenceRoot, packageName, lockInfo, packageCache);
    const packageRel = toPosix(relative(packageRoot(referenceRoot, packageName), filePath));
    return {
      id: `npm:${metadata?.name || packageName}@${metadata?.version || "unknown"}:${packageRel}`,
      kind: "npm",
      path: rel,
      packagePath: packageRel,
      package: metadata,
      sha256: sha256(content),
    };
  }
  if (isWithin(referenceRoot, filePath)) {
    const headBlob = runGit(referenceRoot, ["rev-parse", `HEAD:${rel}`]);
    const worktreeBlob = runGit(referenceRoot, ["hash-object", filePath]);
    return {
      id: `repo:${rel}`,
      kind: "repo",
      path: rel,
      sha256: sha256(content),
      headBlob,
      worktreeBlob,
      dirty: Boolean(headBlob && worktreeBlob && headBlob !== worktreeBlob),
    };
  }
  return {
    id: `outside:${toPosix(filePath)}`,
    kind: "outside",
    path: toPosix(filePath),
    sha256: sha256(content),
  };
}

function declarationNames(ts, statement) {
  const names = [];
  if (
    ts.isFunctionDeclaration(statement) ||
    ts.isClassDeclaration(statement) ||
    ts.isInterfaceDeclaration(statement) ||
    ts.isTypeAliasDeclaration(statement) ||
    ts.isEnumDeclaration(statement)
  ) {
    if (statement.name) names.push(statement.name.text);
  } else if (ts.isVariableStatement(statement)) {
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name)) names.push(declaration.name.text);
    }
  }
  return names;
}

function lineSpan(ts, sourceFile, node) {
  const start = node.getStart(sourceFile);
  const end = node.getEnd();
  const from = sourceFile.getLineAndCharacterOfPosition(start);
  const to = sourceFile.getLineAndCharacterOfPosition(end);
  return {
    offset: start,
    length: end - start,
    line: from.line + 1,
    column: from.character + 1,
    endLine: to.line + 1,
    endColumn: to.character + 1,
  };
}

function importBindings(ts, node) {
  if (!ts.isImportDeclaration(node)) return [];
  const clause = node.importClause;
  if (!clause) return [];
  const bindings = [];
  if (clause.name) {
    bindings.push({ imported: "default", local: clause.name.text, phase: clause.isTypeOnly ? "type" : "runtime" });
  }
  if (clause.namedBindings) {
    if (ts.isNamespaceImport(clause.namedBindings)) {
      bindings.push({ imported: "*", local: clause.namedBindings.name.text, phase: clause.isTypeOnly ? "type" : "runtime" });
    } else {
      for (const element of clause.namedBindings.elements) {
        bindings.push({
          imported: element.propertyName?.text || element.name.text,
          local: element.name.text,
          phase: clause.isTypeOnly || element.isTypeOnly ? "type" : "runtime",
        });
      }
    }
  }
  return bindings;
}

function exportBindings(ts, node) {
  if (!node.exportClause || !ts.isNamedExports(node.exportClause)) return [];
  return node.exportClause.elements.map((element) => ({
    imported: element.propertyName?.text || element.name.text,
    local: element.name.text,
    phase: node.isTypeOnly || element.isTypeOnly ? "type" : "runtime",
  }));
}

function splitByPhase(base, bindings, fallbackPhase) {
  if (bindings.length === 0) return [{ ...base, phase: fallbackPhase, bindings: [] }];
  const output = [];
  for (const phase of ["runtime", "type"]) {
    const selected = bindings.filter((binding) => binding.phase === phase);
    if (selected.length) output.push({ ...base, phase, bindings: selected });
  }
  return output;
}

function extractEdges(ts, sourceFile) {
  const edges = [];
  const nonliteral = [];
  const pushModule = (node, moduleNode, kind, bindings = [], fallbackPhase = "runtime") => {
    if (!moduleNode || !ts.isStringLiteralLike(moduleNode)) {
      nonliteral.push({ kind, expression: moduleNode?.getText(sourceFile) || "<missing>", ...lineSpan(ts, sourceFile, node) });
      return;
    }
    const base = { specifier: moduleNode.text, kind, ...lineSpan(ts, sourceFile, moduleNode) };
    edges.push(...splitByPhase(base, bindings, fallbackPhase));
  };
  const visit = (node) => {
    if (ts.isImportDeclaration(node)) {
      const bindings = importBindings(ts, node);
      pushModule(node, node.moduleSpecifier, bindings.length ? "static-import" : "side-effect-import", bindings);
      return;
    }
    if (ts.isExportDeclaration(node) && node.moduleSpecifier) {
      pushModule(node, node.moduleSpecifier, "re-export", exportBindings(ts, node), node.isTypeOnly ? "type" : "runtime");
      return;
    }
    if (ts.isImportTypeNode(node)) {
      pushModule(node, node.argument?.literal, "import-type", [], "type");
      return;
    }
    if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
      pushModule(node, node.arguments[0], "dynamic-import");
      return;
    }
    if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === "require") {
      pushModule(node, node.arguments[0], "require");
      return;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return { edges, nonliteral };
}

function filterForSymbols(ts, sourceFile, extracted, requestedSymbols) {
  if (!requestedSymbols.length) return { ...extracted, selectedSymbols: [], localSymbolClosure: [] };
  const declarations = new Map();
  for (const statement of sourceFile.statements) {
    for (const name of declarationNames(ts, statement)) declarations.set(name, statement);
  }
  const importLocalNames = new Set(extracted.edges.flatMap((edge) => edge.bindings.map((binding) => binding.local)));
  const queue = [...requestedSymbols];
  const visited = new Set();
  const usedImports = new Set();
  const selectedSymbols = [];
  const missingSymbols = [];
  while (queue.length) {
    const name = queue.shift();
    if (visited.has(name)) continue;
    visited.add(name);
    let declaration = declarations.get(name);
    let displayName = name;
    if (!declaration && name.includes(".")) {
      const [owner, member] = name.split(".", 2);
      const ownerNode = declarations.get(owner);
      if (ownerNode && ts.isClassDeclaration(ownerNode)) {
        declaration = ownerNode.members.find((item) => item.name && item.name.getText(sourceFile) === member);
        displayName = name;
      }
    }
    if (!declaration) {
      missingSymbols.push(name);
      continue;
    }
    selectedSymbols.push({ name: displayName, ...lineSpan(ts, sourceFile, declaration) });
    const visit = (node) => {
      if (ts.isIdentifier(node)) {
        const identifier = node.text;
        if (importLocalNames.has(identifier)) usedImports.add(identifier);
        if (declarations.has(identifier) && !visited.has(identifier)) queue.push(identifier);
      }
      ts.forEachChild(node, visit);
    };
    visit(declaration);
  }
  const edges = extracted.edges.filter(
    (edge) =>
      edge.kind === "side-effect-import" ||
      edge.bindings.length === 0 ||
      edge.bindings.some((binding) => usedImports.has(binding.local))
  );
  return {
    edges,
    nonliteral: extracted.nonliteral.filter((item) =>
      selectedSymbols.some((symbol) => item.offset >= symbol.offset && item.offset < symbol.offset + symbol.length)
    ),
    selectedSymbols,
    localSymbolClosure: [...visited].filter((name) => declarations.has(name)).sort(),
    missingSymbols,
  };
}

function scriptKind(ts, path) {
  const extension = extname(path).toLowerCase();
  if (extension === ".tsx") return ts.ScriptKind.TSX;
  if (extension === ".jsx") return ts.ScriptKind.JSX;
  if ([".js", ".mjs", ".cjs"].includes(extension)) return ts.ScriptKind.JS;
  if (extension === ".json") return ts.ScriptKind.JSON;
  return ts.ScriptKind.TS;
}

function resolveEdge(ts, edge, containingFile, compilerOptions, host, cache, referenceRoot) {
  const resolved = ts.resolveModuleName(edge.specifier, containingFile, compilerOptions, host, cache).resolvedModule;
  const typeResolved = resolved?.resolvedFileName ? resolve(resolved.resolvedFileName) : null;
  let runtimeResolved = null;
  if (edge.phase === "runtime") {
    runtimeResolved = resolvePackageRuntime(referenceRoot, edge.specifier);
    if (!runtimeResolved && typeResolved) {
      runtimeResolved = typeResolved.endsWith(".d.ts") ? withRuntimeExtension(typeResolved.slice(0, -5)) : typeResolved;
    }
  }
  return {
    typeResolved,
    runtimeResolved,
    packageId: resolved?.packageId || null,
    externalLibraryImport: Boolean(resolved?.isExternalLibraryImport),
  };
}

function stableEdgeSort(a, b) {
  return [a.from, a.to || "", a.phase, a.kind, a.specifier, a.offset].join("\0").localeCompare(
    [b.from, b.to || "", b.phase, b.kind, b.specifier, b.offset].join("\0")
  );
}

function tarjan(nodes, edges) {
  const adjacency = new Map(nodes.map((node) => [node.id, []]));
  for (const edge of edges) {
    if (edge.to && adjacency.has(edge.from) && adjacency.has(edge.to)) adjacency.get(edge.from).push(edge.to);
  }
  const indexByNode = new Map();
  const lowByNode = new Map();
  const stack = [];
  const onStack = new Set();
  const components = [];
  let nextIndex = 0;
  const connect = (node) => {
    indexByNode.set(node, nextIndex);
    lowByNode.set(node, nextIndex);
    nextIndex += 1;
    stack.push(node);
    onStack.add(node);
    for (const neighbor of adjacency.get(node) || []) {
      if (!indexByNode.has(neighbor)) {
        connect(neighbor);
        lowByNode.set(node, Math.min(lowByNode.get(node), lowByNode.get(neighbor)));
      } else if (onStack.has(neighbor)) {
        lowByNode.set(node, Math.min(lowByNode.get(node), indexByNode.get(neighbor)));
      }
    }
    if (lowByNode.get(node) === indexByNode.get(node)) {
      const component = [];
      while (stack.length) {
        const member = stack.pop();
        onStack.delete(member);
        component.push(member);
        if (member === node) break;
      }
      if (component.length > 1 || (adjacency.get(node) || []).includes(node)) components.push(component.sort());
    }
  };
  for (const node of [...adjacency.keys()].sort()) if (!indexByNode.has(node)) connect(node);
  return components.sort((a, b) => a[0].localeCompare(b[0]));
}

function mergeEntries(entries) {
  const merged = new Map();
  for (const entry of entries) {
    const current = merged.get(entry.path) || new Set();
    for (const symbol of entry.symbols || []) current.add(symbol);
    merged.set(entry.path, current);
  }
  return [...merged.entries()]
    .map(([path, symbols]) => ({ path, symbols: [...symbols].sort() }))
    .sort((a, b) => a.path.localeCompare(b.path));
}

function nativeContext(nativeRoot, manifestData) {
  const anchors = (manifestData.nativeEntries || [])
    .map((entry) => {
      const filePath = resolve(nativeRoot, entry.path);
      if (!existsSync(filePath) || !statSync(filePath).isFile()) {
        return { path: toPosix(entry.path), symbols: entry.symbols || [], missing: true };
      }
      const content = readFileSync(filePath);
      const relativePath = toPosix(relative(nativeRoot, filePath));
      const headBlob = runGit(nativeRoot, ["rev-parse", `HEAD:${relativePath}`]);
      const worktreeBlob = runGit(nativeRoot, ["hash-object", filePath]);
      return {
        path: relativePath,
        symbols: [...(entry.symbols || [])].sort(),
        sha256: sha256(content),
        headBlob,
        worktreeBlob,
        dirty: Boolean(headBlob && worktreeBlob && headBlob !== worktreeBlob),
        missing: false,
      };
    })
    .sort((a, b) => a.path.localeCompare(b.path));
  return {
    gitHead: runGit(nativeRoot, ["rev-parse", "HEAD"]),
    gitBranch: runGit(nativeRoot, ["branch", "--show-current"]),
    dirty: Boolean(runGit(nativeRoot, ["status", "--porcelain"], "")),
    anchors,
  };
}

function buildGraph(options, manifest, nativeRoot) {
  const referenceRoot = realpathSync(resolve(options.referenceRoot));
  const packageRequire = createRequire(join(referenceRoot, "package.json"));
  const ts = packageRequire("typescript");
  const tsconfigPath = join(referenceRoot, "tsconfig.json");
  const configRead = ts.readConfigFile(tsconfigPath, ts.sys.readFile);
  if (configRead.error) throw new Error(ts.flattenDiagnosticMessageText(configRead.error.messageText, "\n"));
  const config = ts.parseJsonConfigFileContent(configRead.config, ts.sys, referenceRoot);
  const resolutionCache = ts.createModuleResolutionCache(referenceRoot, (name) => name, config.options);
  const entries = mergeEntries(options.entries);
  if (!entries.length) throw new Error("No entries. Supply --manifest or at least one --entry.");

  const lockPath = join(referenceRoot, "yarn.lock");
  const lockInfo = {
    path: existsSync(lockPath) ? "yarn.lock" : null,
    sha256: existsSync(lockPath) ? sha256(readFileSync(lockPath)) : null,
    text: existsSync(lockPath) ? readFileSync(lockPath, "utf8") : null,
  };
  const packageCache = new Map();
  const allowPackages = new Set(options.followPackages);
  const queue = entries.map((entry) => ({
    filePath: resolve(referenceRoot, entry.path),
    depth: 0,
    symbols: entry.symbols,
    explicitSeed: true,
  }));
  const visited = new Set();
  const nodes = [];
  const edges = [];
  const unresolved = [];
  let truncated = null;

  while (queue.length) {
    const item = queue.shift();
    if (visited.has(item.filePath)) continue;
    if (nodes.length >= options.maxNodes) {
      truncated = { reason: "max-nodes", limit: options.maxNodes, remainingQueue: queue.length + 1 };
      break;
    }
    if (!existsSync(item.filePath) || !statSync(item.filePath).isFile()) {
      unresolved.push({ from: null, entry: toPosix(relative(referenceRoot, item.filePath)), reason: "missing-entry" });
      continue;
    }
    visited.add(item.filePath);
    const identity = fileIdentity(referenceRoot, item.filePath, packageCache, lockInfo);
    const content = readFileSync(item.filePath, "utf8");
    const sourceFile = ts.createSourceFile(
      item.filePath,
      content,
      config.options.target || ts.ScriptTarget.Latest,
      true,
      scriptKind(ts, item.filePath)
    );
    const extracted = filterForSymbols(ts, sourceFile, extractEdges(ts, sourceFile), item.symbols || []);
    const node = {
      ...identity,
      language: extname(item.filePath).replace(/^\./, "") || "unknown",
      depth: item.depth,
      explicitSeed: item.explicitSeed,
      selectedSymbols: extracted.selectedSymbols,
      localSymbolClosure: extracted.localSymbolClosure,
      missingSymbols: extracted.missingSymbols || [],
    };
    nodes.push(node);
    for (const dynamic of extracted.nonliteral) {
      unresolved.push({ from: identity.id, reason: "nonliteral-module-specifier", ...dynamic });
    }
    for (const rawEdge of extracted.edges) {
      const resolution = resolveEdge(
        ts,
        rawEdge,
        item.filePath,
        config.options,
        ts.sys,
        resolutionCache,
        referenceRoot
      );
      const targetPath = rawEdge.phase === "runtime" ? resolution.runtimeResolved || resolution.typeResolved : resolution.typeResolved;
      let targetIdentity = null;
      if (targetPath && existsSync(targetPath) && statSync(targetPath).isFile()) {
        targetIdentity = fileIdentity(referenceRoot, targetPath, packageCache, lockInfo);
      }
      let boundary = null;
      if (!targetPath || !targetIdentity) boundary = "unresolved";
      else if (rawEdge.phase === "type" && !options.followTypeOnly) boundary = "type-only-not-followed";
      else if (item.depth >= options.maxDepth) boundary = "max-depth";
      else if (targetIdentity.kind === "outside") boundary = "outside-reference-root";
      else if (targetIdentity.kind === "npm" && !allowPackages.has(targetIdentity.package.name)) {
        boundary = "package-not-allowlisted";
      } else if (["json", "d.ts"].includes(node.language)) boundary = "non-runtime-source";
      const edge = {
        from: identity.id,
        to: targetIdentity?.id || null,
        specifier: rawEdge.specifier,
        kind: rawEdge.kind,
        phase: rawEdge.phase,
        bindings: rawEdge.bindings,
        offset: rawEdge.offset,
        length: rawEdge.length,
        line: rawEdge.line,
        column: rawEdge.column,
        typeResolved: resolution.typeResolved ? toPosix(relative(referenceRoot, resolution.typeResolved)) : null,
        runtimeResolved: resolution.runtimeResolved ? toPosix(relative(referenceRoot, resolution.runtimeResolved)) : null,
        externalLibraryImport: resolution.externalLibraryImport,
        packageId: resolution.packageId,
        boundary,
      };
      edges.push(edge);
      if (boundary === "unresolved") unresolved.push({ from: identity.id, reason: "unresolved-import", ...edge });
      if (!boundary && !visited.has(targetPath)) {
        queue.push({ filePath: targetPath, depth: item.depth + 1, symbols: [], explicitSeed: false });
      }
    }
  }

  nodes.sort((a, b) => a.id.localeCompare(b.id));
  edges.sort(stableEdgeSort);
  unresolved.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const rspackPath = join(referenceRoot, "build-scripts", "rspack.cjs");
  const graph = {
    schemaVersion: "nativeha-ts-dependency-graph/v1",
    tool: {
      version: TOOL_VERSION,
      path: toPosix(relative(nativeRoot, TOOL_PATH)),
      sha256: sha256(readFileSync(TOOL_PATH)),
    },
    reference: {
      root: referenceRoot,
      gitHead: runGit(referenceRoot, ["rev-parse", "HEAD"]),
      gitBranch: runGit(referenceRoot, ["branch", "--show-current"]),
      dirty: Boolean(runGit(referenceRoot, ["status", "--porcelain"], "")),
      tsconfig: { path: "tsconfig.json", sha256: sha256(readFileSync(tsconfigPath)) },
      typescriptVersion: ts.version,
      lockfile: { path: lockInfo.path, sha256: lockInfo.sha256 },
      rspackConfig: existsSync(rspackPath)
        ? { path: "build-scripts/rspack.cjs", sha256: sha256(readFileSync(rspackPath)) }
        : null,
    },
    manifest: manifest.path
      ? { path: toPosix(relative(nativeRoot, manifest.path)), sha256: manifest.sha256, module: manifest.data.module || null }
      : null,
    nativeha: nativeContext(nativeRoot, manifest.data),
    options: {
      entries,
      followPackages: [...allowPackages].sort(),
      followTypeOnly: options.followTypeOnly,
      maxDepth: options.maxDepth,
      maxNodes: options.maxNodes,
      resolutionBasis: "TypeScript bundler resolution plus package exports import/browser/default runtime selection",
    },
    nodes,
    edges,
    cycles: tarjan(nodes, edges),
    unresolved,
    truncated,
  };
  graph.graphFingerprint = sha256(canonicalJSON(fingerprintPayload(graph)));
  return graph;
}

function markdownSummary(graph) {
  const packageNodes = graph.nodes.filter((node) => node.kind === "npm");
  const boundaries = new Map();
  for (const edge of graph.edges) {
    if (edge.boundary) boundaries.set(edge.boundary, (boundaries.get(edge.boundary) || 0) + 1);
  }
  const lines = [
    `# Dependency graph: module ${graph.manifest?.module || "ad hoc"}`,
    "",
    `- Fingerprint: \`${graph.graphFingerprint}\``,
    `- Reference revision: \`${graph.reference.gitHead}\`${graph.reference.dirty ? " (dirty)" : " (clean)"}`,
    `- TypeScript: \`${graph.reference.typescriptVersion}\``,
    `- Nodes: ${graph.nodes.length}; edges: ${graph.edges.length}; cycles: ${graph.cycles.length}`,
    `- Unresolved: ${graph.unresolved.length}; truncated: ${graph.truncated ? "yes" : "no"}`,
    "",
    "## Explicit seeds",
    "",
    ...graph.nodes
      .filter((node) => node.explicitSeed)
      .map(
        (node) =>
          `- \`${node.id}\`${node.selectedSymbols.length ? ` — ${node.selectedSymbols.map((item) => `\`${item.name}\``).join(", ")}` : ""}`
      ),
    "",
    "## Traversed packages",
    "",
    ...(packageNodes.length
      ? [...new Map(packageNodes.map((node) => [node.package.name, node.package])).values()].map(
          (item) => `- \`${item.name}@${item.version}\` (package.json SHA-256 \`${item.packageJSONSha256}\`)`
        )
      : ["- None"]),
    "",
    "## Boundaries",
    "",
    ...([...boundaries.entries()].length
      ? [...boundaries.entries()].sort().map(([name, count]) => `- ${name}: ${count}`)
      : ["- None"]),
    "",
    "## Unresolved or nonliteral edges",
    "",
    ...(graph.unresolved.length
      ? graph.unresolved.slice(0, 50).map((item) => `- \`${item.from || item.entry || "seed"}\`: ${item.reason}`)
      : ["- None"]),
    "",
    "> This file is generated candidate-discovery output. Behavioral conclusions belong in the module evidence packet.",
    "",
  ];
  return lines.join("\n");
}

function writeOutput(path, content) {
  const absolute = resolve(path);
  mkdirSync(dirname(absolute), { recursive: true });
  writeFileSync(absolute, content);
}

function main() {
  try {
    const nativeRoot = runGit(process.cwd(), ["rev-parse", "--show-toplevel"], process.cwd());
    const parsed = parseArgs(process.argv.slice(2));
    const manifest = loadManifest(parsed, nativeRoot);
    const options = mergeOptions(parsed, manifest);
    const graph = buildGraph(options, manifest, nativeRoot);
    if (options.outJson) writeOutput(resolve(nativeRoot, options.outJson), canonicalJSON(graph));
    if (options.outMarkdown) writeOutput(resolve(nativeRoot, options.outMarkdown), markdownSummary(graph));
    if (!options.outJson && !options.outMarkdown) process.stdout.write(canonicalJSON(graph));
    process.stderr.write(
      `trace-ts-deps: ${graph.nodes.length} nodes, ${graph.edges.length} edges, fingerprint ${graph.graphFingerprint}\n`
    );
    if (graph.truncated) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`trace-ts-deps: ${error.stack || error.message}\n`);
    process.exitCode = 1;
  }
}

main();
