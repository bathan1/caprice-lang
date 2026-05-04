type 'k solver = (bool, 'k) Formula.t -> 'k Solution.t
type 'k simplifier = 'k solver -> 'k solver

type 'k validator = (bool, 'k) Formula.t -> bool
(** A validator [validate formula] returns if FORMULA 
    is fully solvable by some solver. *)

type 'k logic = 'k solver * 'k validator
(** A 2 tuple of [SOLVER] and its corresponding [PARTITIONER] is a [LOGIC] *)

module type SOLVABLE = sig
  include Formula.S

  val solve : (bool, 'k) t -> 'k Solution.t
end

let direct_solve (module X : SOLVABLE) : 'k solver = fun e ->
  X.solve (Formula.transform (module X) e)

let cdcl_T ~(theory : 'k Theory.t_solver) (formula : (bool, 'k) Formula.t) : 'k Solution.t =
  let conn = Connector.make () in
  let smt_clauses = Theory.from_smt_formula (Formula.clauses_from formula) in
  let propositional = Connector.abstract conn smt_clauses in
  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | None -> Solution.Unsat
    | Some model ->
      let smt_lits = Connector.literals_from_model conn model in
      match theory smt_lits with
      | Theory_unknown -> Solution.Unknown
      | Theory_sat model -> Solution.Sat model
      | Theory_unsat core ->
        let learned =
          Connector.theory_learn conn core
        in
        loop conn (Sat.Formula.conjoin1 sat_formula learned)
  in
  loop conn propositional

(*
  First attempts to solve with a few heuristics, and then calls the solver.
  This simply special-cases on some common formulas. It also extracts out
  constant assignments (variable = constant).

  As more simplifiers are added, we could instead name this after implied
  concretization.
*)
let rec propagate_constants : 'k simplifier = fun solve expr ->
  let assign i k = Solution.Sat (Model.singleton i k) in
  (* Hand-write a lot of special cases for single formulas *)
  match expr with
  | Const_bool false -> Unsat
  | Const_bool true -> Sat Model.empty
  | Key k ->
    assign true k
  | Not Key k ->
    assign false k
  | Not (Binop (Equal, Key k, Const_int i)) ->
    assign (if i = 0 then 1 else 0) k
  | Binop ((Equal | Less_than_eq), Key (I _ as k), Const_int i)
  | Binop ((Equal | Less_than_eq), Const_int i, Key (I _ as k)) ->
    assign i k
  | Binop (Less_than, Key k, Const_int i) ->
    assign (i - 1) k
  | Binop (Less_than, Const_int i, Key k) ->
    assign (i + 1) k
  | Binop (Less_than, Key (I _ as k), Key (I _ as k'))
  | Binop (Less_than_eq, Key (I _ as k), Key (I _ as k')) ->
    Solution.merge (assign 0 k) (assign 1 k')
  | Binop (Equal, Key k, Key k') ->
    begin match k, k' with
    | I _, I _ -> Solution.merge (assign 0 k) (assign 0 k')
    | B _, B _ -> Solution.merge (assign true k) (assign true k')
    end
  | Not Binop (Equal, Key k, Key k') ->
    begin match k, k' with
    | I _, I _ -> Solution.merge (assign 0 k) (assign 1 k')
    | B _, B _ -> Solution.merge (assign true k) (assign false k')
    end
  | And e_ls ->
    (*
      If there is any (key = int) formula, then we can subst it through, for it
      is an "implied concretization".

      This idea originates with KLEE (https://dl.acm.org/doi/abs/10.5555/1855741.1855756)
      from Section 3.3, paragraph _Constraint Set Simplification_.
    *)
    let find (e : ('a, 'k) Formula.t) : (const:int * (int, 'k) Symbol.t) option =
      match e with
      | Binop (Equal, Key k, Const_int const) -> Some (~const, k)
      | _ -> None
    in
    begin match List.find_map find e_ls with
    | Some (~const, k) ->
      let reduced_expr = Formula.and_ (List.map (Formula.subst const k) e_ls) in
      Solution.merge (propagate_constants solve reduced_expr) (assign const k)
    | None ->
      solve expr
    end
  | _ ->
    solve expr

let linearize next expr =
  next (Integer.linearize expr)

let drop_redundant_ineqs next expr =
  next (Integer.drop_redundant_ineqs expr)

let cdcl_idl expr = cdcl_T ~theory:Idl.idl expr

let contains_unsolvable_binop formula =
  Formula.contains_binop Times formula
  || Formula.contains_binop Divide formula
  || Formula.contains_binop Modulus formula
  || Formula.contains_binop Plus formula

let try_idl ~(threshold : int) (next : 'k solver) (formula : (bool, 'k) Formula.t) =
  if contains_unsolvable_binop formula then next formula
  else
    match formula with
    | Const_bool true -> Solution.Sat Model.empty
    | Const_bool false -> Solution.Unsat
    | _ ->
      let formula', num_cases = Idl.split_cases formula in
      if num_cases > threshold then next formula
      else
        match cdcl_idl formula' with
        | Solution.Unknown ->
          next formula
        | solution -> solution

(*
  Right-associative simplifier composition.
  E.g. this simplifier
    simpl1 @> simpl2 @> simpl3
  is equivalent to
    simpl1 @> (simpl2 @> simpl3)
  which we can see does simpl1 as a pre-pass to the composition of simpl2
  and simpl3. Hence when given a solver, this first simplifies with simpl1,
  then with simpl2, and finally with simpl3 before calling the solver.
*)
let ( @> ) : 'k simplifier -> 'k simplifier -> 'k simplifier =
  fun f g -> fun solve -> g (f solve)

let ( @@> ) : 'k simplifier -> 'k simplifier -> 'k simplifier =
  fun f g -> fun solve -> f (g solve)

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  (* let ascii_key k = Symbol.AsciiSymbol.to_string @@ Model.uid_from_key k in *)
  let intstring_key k = k
    |> Model.uid_from_key
    |> Utils.Uid.to_int
    |> Int.to_string
    |> Printf.sprintf "<%s>"
  in
  let pipeline =
    propagate_constants
    @@> (fun next expr ->
      let result = Integer.linearize expr in
      Printf.printf "[linearize] before = %s | after = %s\n" (Formula.to_string expr ~key:intstring_key) (Formula.to_string result ~key:intstring_key);
      next result)
    @@> (fun next expr ->
      let result = Integer.drop_redundant_ineqs expr in
      Printf.printf "[drop_redundant_ineqs] before = %s | after = %s\n" (Formula.to_string expr ~key:intstring_key) (Formula.to_string result ~key:intstring_key);
      next result)
  in
  pipeline (direct_solve (module Oracle))
