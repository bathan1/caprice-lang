import { cp, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const exampleDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = path.resolve(exampleDir, "../..");
const buildDir = path.join(repositoryRoot, "_build/default/src/wasm");
const outputDir = path.join(exampleDir, "public/caprice-wasm");

await mkdir(outputDir, { recursive: true });
await cp(
  path.join(buildDir, "main.bc.wasm.js"),
  path.join(outputDir, "main.bc.wasm.js"),
);
await cp(
  path.join(buildDir, "main.bc.wasm.assets"),
  path.join(outputDir, "main.bc.wasm.assets"),
  { recursive: true },
);

