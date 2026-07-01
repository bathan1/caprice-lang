#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const loaderPath = path.resolve(
  __dirname,
  "../_build/default/src/wasm/main.bc.wasm.js",
);

if (!fs.existsSync(loaderPath)) {
  console.error("The WebAssembly build was not found.");
  console.error("Build it with: dune build src/wasm/main.bc.wasm.js");
  process.exitCode = 1;
  return;
}

function waitForExport(name) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error(`Timed out waiting for globalThis.${name}`)),
      10_000,
    );

    const check = () => {
      if (globalThis[name]) {
        clearTimeout(timeout);
        resolve(globalThis[name]);
      } else {
        setImmediate(check);
      }
    };

    check();
  });
}

async function main() {
  // wasm_of_ocaml's Node loader locates its asset directory relative to
  // require.main.filename. Point that at the generated loader while it starts.
  const entryFilename = require.main.filename;
  require.main.filename = loaderPath;

  try {
    require(loaderPath);
    const caprice = await waitForExport("capriceWasm");
    const result = caprice.solveSmokeTest();

    console.log(`Caprice smoke test: ${result}`);
  } finally {
    require.main.filename = entryFilename;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
