(lang dune 3.21)

(name caprice)

(using menhir 3.0)

(generate_opam_files true)

(license MIT)

(authors "Brandon Stride <bstride1@jhu.edu")

(maintainers "Brandon Stride <bstride1@jhu.edu")

(package
 (name caprice)
 (description "Semantic type refutation via concolic semantics")
 (depends
  alcotest
  baby
  benchmark
  cmdliner
  js_of_ocaml
  js_of_ocaml-ppx
  menhir
  mtime
  (ocaml (>= 5.5.0))
  psq
  wasm_of_ocaml-compiler
  yojson
  z3
  ))
