open Utils
open Formula

module type SOLVABLE = sig
  include Formula.S

  val solve : (bool, 'k) t -> 'k Solution.t
end

let direct_solve (module X : SOLVABLE) : 'k solver = fun e ->
  X.solve (Formula.transform (module X) e)

(*
  First attempts to solve with a few heuristics, and then calls the solver.
  This simply special-cases on some common formulas. It also extracts out
  constant assignments (variable = constant).

  Since the `binop` function in Formula turns greater-thans into less-thans, we
  don't handle any greater-than in the cases below--it will never happen since
  the user can only construct formulas with the smart constructors.
  Similarly, we will not get "not" of an inequality operator.

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

(** TODO: Port over `bellman_ford` + friends here. *)
let integer_difference : 'k simplifier = 
  fun solve expr ->
    solve expr

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
let (@>) : 'k simplifier -> 'k simplifier -> 'k simplifier =
  fun f g ->
    fun solve ->
      g (f solve)

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  let pipeline = Integer.simplify_int_bounds
  @> propagate_constants
  @> integer_difference 
  in
  pipeline (direct_solve (module Oracle))

