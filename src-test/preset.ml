
open Ctl_ast
open Variables

type t = Preset of Ident.t [@@unboxed]

let s (Ident.Ident id) = id

(*
  Preset: splaying can quickly prove this well typed.

  (* TEST
    typing = exhausted;
    speed = fast;
    flags += " -s -r";
    typecheck; 
  *)
    ===
  (* TEST 
    include splayable;
  *)
*)
let splayable : Ctl_ast.t =
  [ Env_stmt (Assign (speed, s fast))
  ; Env_stmt (Assign (typing, s exhausted))
  ; Env_stmt (Append (flags, " -s -r"))
  ; Test Typecheck
  ]

(*
  Preset: there is a refutation, i.e. a path that shows the program is ill-typed.

  (* TEST
    typing = ill-typed;
    speed = fast;
    flags += " -r";
    typecheck; 
  *)
    ===
  (* TEST 
    include refutable;
  *)
*)
let refutable : Ctl_ast.t =
  [ Env_stmt (Assign (speed, s fast))
  ; Env_stmt (Assign (typing, s ill_typed))
  ; Env_stmt (Append (flags, " -r"))
  ; Test Typecheck
  ]

(*
  Preset: there are naturally finitely many paths.

  (* TEST
    typing = exhausted;
    speed = fast;
    flags += " -r";
    typecheck; 
  *)
    ===
  (* TEST 
    include finite-well-typed;
  *)
*)
let finite_well_typed : Ctl_ast.t =
  [ Env_stmt (Assign (speed, s fast))
  ; Env_stmt (Assign (typing, s exhausted))
  ; Env_stmt (Append (flags, " -r"))
  ; Test Typecheck
  ]

(*
  Preset: there are infinitely many paths, and splaying would be
    incomplete; we are expecting timeout.

  (* TEST
    typing = no-error;
    speed = slow;
    flags += " -t 3.0 -r";
    typecheck; 
  *)
    ===
  (* TEST 
    include diverges;
  *)
*)
let diverges : Ctl_ast.t =
  [ Env_stmt (Assign (speed, s slow))
  ; Env_stmt (Assign (typing, s no_error))
  ; Env_stmt (Append (flags, " -t 3.0 -r"))
  ; Test Typecheck
  ]

let lookup : ident -> Ctl_ast.t = function
  | Ident "finite-well-typed" -> finite_well_typed
  | Ident "splayable" -> splayable
  | Ident "refutable" -> refutable
  | Ident "diverges" -> diverges
  | _ -> []
