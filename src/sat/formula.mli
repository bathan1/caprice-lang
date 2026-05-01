open Utils

type literal = private
  | Pos of Uid.t
  | Neg of Uid.t

type clause = literal list

type t = clause list

val pos : int -> literal
val neg : int -> literal

val negate : literal -> literal

val is_empty : clause -> bool
val is_unit_clause : clause -> bool

val key : literal -> Uid.t

val find_free_variable : Uid.t list -> t -> Uid.t option

val is_tautology : t -> bool

val disjoin : clause -> clause -> clause

val conjoin1 : t -> clause -> clause list

val conjoin : t list -> t

val resolve_pair : clause -> clause -> clause

val pp_lit : out_channel -> literal -> unit

val pp_clause : out_channel -> clause -> unit

val pp_formula : out_channel -> t -> unit
