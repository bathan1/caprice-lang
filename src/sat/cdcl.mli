(* Boolean SAT solver loop core *)

(** [next] is the message type that indicates the next step 
    the main loop should propagate onto a solver state [t] *)
type next =
  | Decide
  | Conflict of Formula.literal list
  | Implication of Formula.literal list * Formula.literal

(** [cdcl formula] returns some list of literals that satisfies FORMULA if
    it exists. Otherwise, it returns [None] to indicate FORMULA is unsatisfiable *)
val cdcl : Formula.formula -> Formula.literal list option

val pp_next : uid:(Utils.Uid.t -> string) -> Format.formatter -> next -> unit
