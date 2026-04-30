open Utils

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

type ('a, 'k) key_value = ('a, 'k) Symbol.t * value:'a
type 'k assignment =
  | Assign : ('a, 'k) key_value -> 'k assignment

let rec find_unit_literal (f : (bool, 'k) Formula.t) : 'k assignment option =
  match f with
  | Formula.Key bool_symbol -> Some (Assign (bool_symbol, ~value:true))
  | Binop (Equal, Key k, Const_int value) -> Some (Assign (k, ~value))
  | Not f ->
    begin match find_unit_literal f with
    | None -> None
    | Some assignment ->
      match assignment with
      | Assign (I _ as key, ~value) -> Some (Assign (key, ~value:(if value = 0 then 1 else 0)))
      | Assign (B _ as key, ~value) -> Some (Assign (key, ~value:(not value)))
    end
  | _ -> None

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

let find_first_unit_literal (ls : (bool, 'k) Formula.t list) :
    ((bool, 'k) Symbol.t * bool) option =
  List.find_map
    (function
      | Formula.Key key -> Some (key, true)
      | Not (Key key) -> Some (key, false)
      | _ -> None)
    ls

let unit_propagate (clauses : (bool, 'k) Formula.t list) :
    (bool, 'k) Formula.t list * bool Uid.Map.t =
  let rec propagate clauses truth_tbl =
    match find_first_unit_literal clauses with
    | None -> clauses, truth_tbl
    | Some (key, value) -> 
      let uid = Symbol.to_uid key in
      let next_truthtbl = Uid.Map.add uid value truth_tbl in
      let next = List.map (Formula.subst value key) clauses in
      match next with
      | [] -> clauses, next_truthtbl
      | [hd] -> ([ hd ], next_truthtbl)
      | next -> propagate next next_truthtbl
  in
  propagate clauses Uid.Map.empty

(** [choose_literal formula] picks the first Key from the left from the unit-clause pruned FORMULA.
    It throws if there is no symbol found
*)
let rec choose_literal : type k. (bool, k) Formula.t list -> (bool, k) Symbol.t option = 
  function
  | [] -> None
  | hd :: tl -> (
      match hd with
      | Formula.Not Key key | Key key -> Some key
      | Binop (Or, Key key, _) -> Some key
      | Binop (Or, _, Key key) -> Some key
      | _ -> choose_literal tl)

(** [contains_const_false ls] returns if an immediate element of LS is
    a [Formula.Const_bool false].
*)
let contains_const_false ls = List.exists
  (function
  | Formula.Const_bool false -> true
  | _ -> false) 
  ls

let is_falsified_clause (model_state : bool Uid.Map.t) (vars : Uid.Set.t) : bool =
  Uid.Set.for_all (fun symbol ->
    match Uid.Map.find_opt symbol model_state with
    | None -> false
    | Some v -> not v) vars

let choose_solver
  (logics : 'k logic list)
  (formula : (bool, 'k) Formula.t)
  : 'k solver option =
  List.find_map (fun (solver, is_solvable) -> 
    if is_solvable formula then Some solver
    else None) logics

let check
  (type k)
  (logics : k logic list)
  (formula : (bool, k) Formula.t)
  : k Solution.t =
  match choose_solver logics formula with
  | None -> Solution.Unknown
  | Some solve -> solve formula

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

let is_trivial_true model keys =
  Uid.Set.for_all (fun uid ->
    match Uid.Map.find_opt uid model with
    | None -> false
    | Some v -> v
  ) keys

let dpll
  ?(to_symbol : int -> (bool, 'k) Symbol.t =
    fun i -> i |> Uid.of_int |> fun uid -> Symbol.B uid)
  (solve_next : 'k solver)
  (formula : (bool, 'k) Formula.t)
  : 'k Solution.t =
  let props, map = Integer.to_propositional ~to_symbol formula in
  let to_logical = fun uid -> Uid.Map.find uid map in
  let clauses = Formula.clauses_from props in
  let rebuild_logical model =
    Formula.and_
      (model |> Uid.Map.to_list
      |> List.map (fun (uid, tv) ->
          let formula = to_logical uid in
          if tv then formula else Formula.not_ formula))
  in
  let rec dpll clauses model_state =
    let propagated, partial_model = unit_propagate clauses in 
    let curr_model = Uid.Map.union (fun _ _ new_v -> Some new_v) model_state partial_model in
    match propagated with
    | [] -> Solution.Unsat
    | ls when contains_const_false ls -> Solution.Unsat
    | ls when List.for_all (
        function
        | Formula.Const_bool true -> true
        | _ -> false
      ) ls -> solve_next (rebuild_logical curr_model)
    | propagated ->
        let branch_key = (
          match choose_literal propagated with
          | None -> failwith (
            Printf.sprintf "Couldn't choose literal for unit propagated %s\n"
            (Formula.to_string ~uid:Symbol.AsciiSymbol.to_string (Formula.and_ propagated))
          )
          | Some key -> key
        ) in
        let next_formula = Formula.and_ propagated in
        let uid = Symbol.to_uid branch_key in
        let true_model = Uid.Map.add uid true curr_model in
        let true_clauses = Formula.clauses_from (
          Formula.subst true branch_key next_formula
        ) in
        match true_clauses with
        | [ Const_bool true ] ->
            solve_next (rebuild_logical true_model)
        | true_clauses -> (
            match dpll true_clauses true_model with
            | Solution.Unsat ->
                let false_model = Uid.Map.add uid false curr_model in
                let false_clauses = Formula.clauses_from (
                  Formula.subst false branch_key next_formula
                ) in
                dpll false_clauses false_model
            | s -> s)
  in
  dpll clauses Uid.Map.empty

let dpll_simplify : type k. k solver -> (bool, k) Formula.t -> k Solution.t =
  fun solve formula ->
    dpll
      ~to_symbol:(fun off ->
        off + Char.code 'p' |> Utils.Uid.of_int |> fun uid -> Symbol.B uid)
      solve
      formula

let logics : 'k logic list = [
  (Integer.solve_idl, Integer.is_idl_solvable)
]

let fastcheck_is_unsolvable expr = 
  Formula.contains_binop Binop.Modulus expr ||
  Formula.contains_binop Binop.Divide expr ||
  Formula.contains_binop Binop.Times expr

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  let pipeline =
    propagate_constants
    @> (fun next expr -> next (Integer.rewrite_bounds expr))
    @> (fun next expr ->
      if fastcheck_is_unsolvable expr then next expr
      else
        match choose_solver logics expr with
        | None ->
          next expr
        | Some solve -> dpll_simplify solve expr
    )
  in
  pipeline (direct_solve (module Oracle))
