(* The Integer Difference Logic module is responsible for solving
   formula terms *)

val solve_diff_logic : 'k Theory.literal list -> 'k Theory.theory_solution
(** [solve_diff_logic lits] finds the tightest upper bounds of each integer 
    variable in LITS and packs them into a [Model.t], if they exist. 

    If there are any [Not (Binop (Equal, _, _)] literals, then this returns
    the implied literals from those neqs as the [Theory_split].

    Otherwise, a contradiction was detected, so this will return the 
    UNSAT core literals that made up the contradiction so that CDCL loop 
    can advance. In the case of IDL, a contradiction means a negative cycle
    was detected in the underlying graph search proc. *)
