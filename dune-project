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
  menhir
  mtime
  (ocaml (>= 5.4.0))
  ppx_deriving
  psq
  z3
  ))
