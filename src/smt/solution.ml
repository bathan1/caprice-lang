type 'k t =
  | Sat of 'k Model.t
  | Unknown
  | Unsat

type ('k, 'core) theory_solution =
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'core
  | Theory_unknown

let from_theory (theory : ('k, 'core) theory_solution) : 'k t =
  match theory with
  | Theory_unknown -> Unknown
  | Theory_unsat _ -> Unsat
  | Theory_sat model -> Sat model

let merge (x : 'k t) (y : 'k t) : 'k t =
  match x, y with
  | Unsat, _ | _, Unsat -> Unsat
  | Unknown, _ | _, Unknown -> Unknown
  | Sat m1, Sat m2 -> Sat (Model.merge m1 m2)

let to_string
  (type k)
  (solution : k t)
  ~(key : k Model.key -> string)
  : string =
  match solution with
  | Unknown -> "\"Unknown\""
  | Unsat -> "\"Unsat\""
  | Sat model -> Model.to_string model ~key

let pp_solution
  (type k)
  ~(key : k Model.key -> string)
  (fmt : Format.formatter)
  (solution : k t)
  : unit =
  match solution with
  | Unknown ->
    Format.fprintf fmt "Unknown"

  | Unsat ->
    Format.fprintf fmt "Unsat"

  | Sat model ->
    Format.fprintf fmt "Sat %a" (Model.pp_key ~key) model

let pp_theory_solution
  (type k core)
  ~(key : k Model.key -> string)
  (pp_core : Format.formatter -> core -> unit)
  (fmt : Format.formatter)
  (solution : (k, core) theory_solution)
  : unit =
  match solution with
  | Theory_unknown ->
    Format.fprintf fmt "Theory_unknown"
  | Theory_unsat core ->
    Format.fprintf fmt "Theory_unsat %a" pp_core core
  | Theory_sat model ->
    Format.fprintf fmt "Theory_sat %a" (Model.pp_key ~key) model
