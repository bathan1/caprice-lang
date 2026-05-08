(* The Connector is the 'glue' layer between the CDCL SAT solver and
   the Theory layer. It is responsible for mapping the propositional
   SAT formula atoms with those from the SMT formula. *)

open Utils

type 'k t

val make : int -> 'k t

val abstract : ?uid:(int -> Uid.t) -> 'k Theory.formula -> 'k t -> Sat.Formula.formula

val abstract_clause : ?uid:(int -> Uid.t) -> 'k Theory.clause -> 'k t -> Sat.Formula.clause

val make_theory_literals : Sat.Model.model -> 'k t -> 'k Theory.literal list

val theory_learn : 'k Theory.core -> 'k t -> Sat.Formula.clause
