# Caprice WebAssembly target

This target runs the standard SMT pipeline:

1. formula simplification and linearization;
2. Blue3 with the built-in integer-difference-logic theory solver;
3. a dummy fallback backend that returns `Unknown`.

The fallback deliberately has no dependency on Z3. Build the target with:

```sh
opam install wasm_of_ocaml-compiler js_of_ocaml js_of_ocaml-ppx
dune build src/wasm/main.bc.wasm.js
```

`wasm_of_ocaml-compiler` requires Binaryen 119 or newer. Verify this with
`wasm-opt --version` before installing the opam dependencies. The opam
`conf-binaryen` package only checks that the executable exists, so an older
system package can pass dependency resolution and then fail the compiler build
with errors such as `Unknown option '--enable-strings'`.

The build produces the JavaScript loader at
`_build/default/src/wasm/main.bc.wasm.js` and its WebAssembly assets beside it.

The loader exports `globalThis.capriceWasm.solveSmokeTest()`. It solves a
contradictory pair of integer difference constraints through Blue3 and returns
`"Unsat"`.

The loader also exports `globalThis.capriceWasm.solveInput(text)`. It accepts
integer comparisons, arithmetic `+` and `-`, boolean `^`/`&&`, `|`/`||`, and
`not`/`!`, with `#` line comments, and returns a model, `"Unsat"`, `"Unknown"`,
or a prefixed parse error.

After building, run the Node.js example from the repository root:

```sh
node examples/use-wasm.cjs
```
