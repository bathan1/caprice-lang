(** A ['k atom] captures all structs that are boolean in value for a formula with 'k keys *)
type 'k atom =
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom

(** A ['k literal] is either an SMT ['k atom] or the negation NEG of the atom *)
type 'k literal =
  | Pos of 'k atom
  | Neg of 'k atom

(** A ['k theory_solution] is a domain specific theory solution 'instantiated'
    by the parent ['k] formula key. It is one of...

    1. [Theory_sat model] is a concrete [Model.t] that satisfies
       some given set of conjunctive difference literals

    2. [Theory_unsat core] is a list of the ['k] literals that
       resulted in a contradiction from the theory solver.

    3. [Theory_split splits] is the list of clauses that represents one conjunction
       of many disjunctions, which can be used as a case split by the
       boolean solver. *)
type 'k theory_solution =
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'k literal list
  | Theory_split of 'k literal list list

(** A ['k theory_solver] accepts a list implied to be in a conjunction and returns its domain specific ['k t_solution] *)
type 'k theory_solver = 'k literal list -> 'k theory_solution

(** [from_smt_formula formula] maps CNF FORMULA to their explicit nested
    disjunction list. If FORMULA is not in CNF this throws. *)
val from_smt_formula : (bool, 'k) Formula.t -> 'k literal list list

val pp_atom : key:(Model.key -> string) -> Format.formatter -> 'k atom -> unit
val pp_literal : key:(Model.key -> string) -> Format.formatter -> 'k literal -> unit
val pp_clause : key:(Model.key -> string) -> Format.formatter -> 'k literal list -> unit
val pp_delim_literals : ?delim:string -> key:(Model.key -> string) -> Format.formatter -> 'k literal list -> unit
val pp_unit_literals : key:(Model.key -> string) -> Format.formatter -> 'k literal list -> unit
val pp_formula : key:(Model.key -> string) -> Format.formatter -> 'k literal list list -> unit
val pp_theory_solution : key:(Model.key -> string) -> Format.formatter -> 'k theory_solution -> unit
