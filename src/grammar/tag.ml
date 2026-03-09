
type reason =
  | GenList             (* generate empty or cons *)
  | CheckList           (* check hd or tl *)
  | CheckTuple          (* check left or right side of tuple *)
  | CheckSingleton      (* check subset or superset or intensional equality *)
  | CheckGenFun         (* check domain or codomain *)
  | CheckWrappedFun     (* check domain or codomain of a wrapped function *)
  | CheckRefinementType (* check underlying type or evaluate the predicate *)
  | CheckLetExpr        (* type check a let-expression, or eval body *)
  | ApplGenFun          (* type check argument, or generate result *)
  | ApplWrappedFun      (* type check argument, or evaluate body *)

let reason_to_string = function
  | GenList             -> "Generate list"
  | CheckList           -> "Check list"
  | CheckTuple          -> "Check tuple"
  | CheckSingleton      -> "Check singleton"
  | CheckGenFun         -> "Check generated function"
  | CheckWrappedFun     -> "Check wrapped function"
  | CheckRefinementType -> "Check refinement type"
  | CheckLetExpr        -> "Check let-expression"
  | ApplGenFun          -> "Apply generated function"
  | ApplWrappedFun      -> "Apply wrapped function"

type dir =
  | Gen   (* the label is used to generate something *)
  | Check (* the label is used to check something *)

type t =
  | Left of reason
  | Right of reason
  | Label of Lang.Ident.t * dir

let of_variant_label dir vlabel =
  Label (Lang.Labels.Variant.to_ident vlabel, dir)

let of_record_label dir rlabel =
  Label (Lang.Labels.Record.to_ident rlabel, dir)

let priority = function
  | Label (_, Gen) -> Path_priority.one
  | Label (_, Check) -> Path_priority.zero
  | (Left reason | Right reason) ->
    match reason with
    | GenList -> Path_priority.one
    | _ -> Path_priority.zero

let to_string = function
  | Left reason -> Format.sprintf "Left (%s)" (reason_to_string reason)
  | Right reason -> Format.sprintf "Right (%s)" (reason_to_string reason)
  | Label (Ident s, Check) -> Format.sprintf "%s (Check)" s
  | Label (Ident s, Gen) -> Format.sprintf "%s (Gen)" s
