# Caprice Vite + React example

From the repository root, build the WebAssembly module:

```sh
dune build src/wasm/main.bc.wasm.js
```

Then start the example:

```sh
cd examples/vite-react-wasm
pnpm install
pnpm dev
```

The page loads the generated Caprice WebAssembly module and sends the entered
integer constraint formula to `solveInput()`. The original `solveSmokeTest()`
export remains available for compatibility.
