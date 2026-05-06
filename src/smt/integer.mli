(* The Integer module holds the simplifiers / helper functions that handle
   int-sorted formula fragments. *)

type affine =
(** An integer affine term restricted to the IDL-friendly shape [x + c] or [c].
    [Var_plus_const (x, c)] represents [x + c]. *)
  | Const of int
  | Var_plus_const of Utils.Uid.t * int

val affine_from_formula_opt : ('a, 'k) Formula.t -> affine option
(** [affine_from_formula_opt formula] Attempts to view FORMULA as an IDL affine expression.

    Returns [Some (Const c)] for integer constants, [Some (Var_plus_const (x, c))]
    for terms equivalent to [x + c], and [None] for terms that are not supported
    by the restricted affine fragment, such as multiplication or expressions with
    more than one variable. *)

val reflect_int_opt : ('a, 'k) Formula.t -> (int, 'k) Formula.t option
(** [reflect_int_opt formula] returns the FORMULA itself as 
    a concrete Int sorted [Formula.t] type if FORMULA is an int formula *)

val linearize : (bool, 'k) Formula.t -> (bool, 'k) Formula.t
(** [linearize formula] performs a few int-based heuristics to reduce FORMULA to an equisatisfiable formula. *)

val drop_redundant_ineqs : (bool, 'k) Formula.t -> (bool, 'k) Formula.t
(** [drop_redundant_ineqs formula] drops redundant inequalities from FORMULA *)
