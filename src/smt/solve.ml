open Formula
open Utils

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

let dpll 
  ?(leftovers : Uid.t -> bool = fun _ -> Random.bool ())
  ?(to_symbol : int -> (bool, 'k) Symbol.t
    = fun i ->
      i
      |> Uid.of_int
      |> fun uid -> Symbol.B uid
    )
  ~(solvers : 'k Formula.solver list)
  (solve_next : 'k Formula.solver)
  (f : (bool, 'k) Formula.t)
  : 'k Solution.t =
  f
  |> Integer.rewrite
  |> fun rewritten ->
    let check_for_unsolvable op = Formula.contains_binop op rewritten in
    if 
      check_for_unsolvable Times ||
      check_for_unsolvable Modulus ||
      check_for_unsolvable Divide
    then
      solve_next f
    else
      rewritten
  |> Integer.to_propositional ~to_symbol
  |> fun (props, map) ->
  let rec check : (bool, 'k) Formula.t -> bool =
    function
    | Formula.Key _ -> true
    | Binop (Or, left, right) -> check left && check right
    | _ -> false
  in
  let mapped_ok = List.for_all check (Formula.clauses_of props) in
  if not mapped_ok then
    solve_next f
  else
  let keyset = Formula.symbols f in
  let decode = fun uid -> Uid.Map.find uid map in
  let clauses = Formula.clauses_of props in
  let rebuild_logical model = Formula.and_ (
    model
    |> Uid.Map.to_list
    |> List.map (fun (uid, tv) ->
      let formula = decode uid in
      if tv then
        formula
      else
        Formula.not_ formula
    )
  ) in
  let rec dpll clauses model_state =
    let curr_keyset = 
      clauses 
      |> List.map Formula.symbols 
    in
    if
      List.is_empty curr_keyset || List.exists (Boolean.is_falsified_clause model_state) curr_keyset
    then 
      if List.is_empty curr_keyset then
        (* 
           TODO: This means sat at the bool level, so try model_state solution...
        *)
        Solution.Unsat
      else
        Solution.Unsat
    else
      let is_trivial_true = match clauses with | [Const_bool true] -> true | _ -> false in
      let is_sat = is_trivial_true || (
        curr_keyset
        |> List.for_all (fun uids ->
          uids
          |> Uid.Set.exists (fun uid -> 
            match Uid.Map.find_opt uid model_state with
            | None -> false
            | Some v -> v
          )
        )
      ) in
      if is_sat then 
        let final_model = Uid.Map.add_seq (
          model_state
          |> Uid.Map.domain
          |> Uid.Set.to_seq
          |> Seq.map (fun key -> key, leftovers key)
        ) model_state in
          Boolean.try_solvers solvers (rebuild_logical final_model) keyset
      else
        let reduced, model = (
          clauses
          |> Boolean.unit_propagate
          |> fun (e, partial) -> 
          e, 
          model_state 
          |> Uid.Map.union (fun _ _ new_v -> Some new_v) partial
        )
        in
        match reduced with
          | [] -> failwith "HANDLEME"
        | clauses when 
          clauses 
          |> List.for_all (
            function 
            | Formula.Const_bool true -> true 
            | _ -> false
          ) -> 
          Boolean.try_solvers solvers (rebuild_logical model) keyset
        | ls when List.exists (function Formula.Const_bool false -> true | _ -> false) ls -> 
          Solution.Unsat
        | next ->
          let branch_key = Boolean.choose_literal next in
          let uid = Symbol.to_uid branch_key in 
          let left_model = (Uid.Map.add uid true model) in
          let next = 
            Formula.and_ next
            |> Formula.subst true branch_key
            |> fun f -> 
              Formula.clauses_of f
          in
          begin match next with
          | [Const_bool true] ->
              Boolean.try_solvers solvers (rebuild_logical left_model) keyset
          | next ->
            match dpll next left_model with
            | Solution.Unsat ->
              let right_model = (Uid.Map.add uid false model) in
              dpll next right_model
            | s -> s
          end
  in
  dpll clauses Uid.Map.empty
  |> function
    | Solution.Unknown -> solve_next f
    | s -> s
;;

[@@@ocaml.warning "-48"]
let dpll_simplify : 'k simplifier = 
  dpll
  ~to_symbol:(fun off ->
    off + (Char.code 'p')
    |> Utils.Uid.of_int
    |> fun uid -> Symbol.B uid
  )
  ~solvers:[Integer.solve_int_diff]
;;

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  let pipeline = Integer.simplify
  @> propagate_constants
  @> dpll_simplify
  in
  pipeline (direct_solve (module Oracle))

