open Utils
module IntSet = Set.Make (Int)

type 'k solver = (bool, 'k) Formula.t -> 'k Solution.t
type 'k simplifier = 'k solver -> 'k solver

type 'k partitioner = (bool, 'k) Formula.t -> int list * int list
(** A partitioner is a function [partition f] that partitions ORDERED clauses F
    into a [(SOLVABLE_INDICES, UNSOLVABLE_INDICES)] formula tuple *)

type 'k logic = 'k solver * 'k partitioner
(** A 2 tuple of [SOLVER] and its corresponding [PARTITIONER] is a [LOGIC] *)

module type SOLVABLE = sig
  include Formula.S

  val solve : (bool, 'k) t -> 'k Solution.t
end

let direct_solve (module X : SOLVABLE) : 'k solver =
 fun e -> X.solve (Formula.transform (module X) e)

(*
  First attempts to solve with a few heuristics, and then calls the solver.
  This simply special-cases on some common formulas. It also extracts out
  constant assignments (variable = constant).

  As more simplifiers are added, we could instead name this after implied
  concretization.
*)
let rec propagate_constants : 'k simplifier =
 fun solve expr ->
  let assign i k = Solution.Sat (Model.singleton i k) in
  (* Hand-write a lot of special cases for single formulas *)
  match expr with
  | Formula.Const_bool false -> Unsat
  | Const_bool true -> Sat Model.empty
  | Key k -> assign true k
  | Not (Key k) -> assign false k
  | Not (Binop (Equal, Key k, Const_int i)) -> assign (if i = 0 then 1 else 0) k
  | Binop ((Equal | Less_than_eq), Key (I _ as k), Const_int i)
  | Binop ((Equal | Less_than_eq), Const_int i, Key (I _ as k)) ->
      assign i k
  | Binop (Less_than, Key k, Const_int i) -> assign (i - 1) k
  | Binop (Less_than, Const_int i, Key k) -> assign (i + 1) k
  | Binop (Less_than, Key (I _ as k), Key (I _ as k'))
  | Binop (Less_than_eq, Key (I _ as k), Key (I _ as k')) ->
      Solution.merge (assign 0 k) (assign 1 k')
  | Binop (Equal, Key k, Key k') ->
      begin match (k, k') with
      | I _, I _ -> Solution.merge (assign 0 k) (assign 0 k')
      | B _, B _ -> Solution.merge (assign true k) (assign true k')
      end
  | Not (Binop (Equal, Key k, Key k')) ->
      begin match (k, k') with
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
      let find (e : ('a, 'k) Formula.t) :
          (const:int * (int, 'k) Symbol.t) option =
        match e with
        | Binop (Equal, Key k, Const_int const) -> Some (~const, k)
        | _ -> None
      in
      begin match List.find_map find e_ls with
      | Some (~const, k) ->
          let reduced_expr =
            Formula.and_ (List.map (Formula.subst const k) e_ls)
          in
          Solution.merge
            (propagate_constants solve reduced_expr)
            (assign const k)
      | None -> solve expr
      end
  | _ -> solve expr

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
    | None -> (clauses, truth_tbl)
    | Some (key, value) -> (
        let clauses_anded = Formula.and_ clauses in
        let uid = Symbol.to_uid key in
        let next_truthtbl = Uid.Map.add uid value truth_tbl in
        let next = Formula.subst value key clauses_anded in
        match next with
        | And next_ls -> propagate next_ls next_truthtbl
        | rest -> ([ rest ], next_truthtbl))
  in
  propagate clauses Uid.Map.empty

let rec choose_literal : type k. (bool, k) Formula.t list -> (bool, k) Symbol.t
    = function
  | [] -> failwith "oops"
  | hd :: tl -> (
      match hd with
      | Formula.Key key -> key
      | Formula.Binop (Binop.Or, Formula.Key key, _) -> key
      | Formula.Binop (Binop.Or, _, Formula.Key key) -> key
      | _ -> choose_literal tl)

let formula_to_clauses = function Formula.And ls -> ls | e -> [ e ]

(** [contains_const_false ls] returns if an immediate element of LS is 
    a [Formula.Const_bool false].
*)
let contains_const_false ls = List.exists (
  function
  | Formula.Const_bool false -> true
  | _ -> false
) ls

let is_falsified_clause (model_state : bool Uid.Map.t) (vars : Uid.Set.t) : bool
    =
  vars
  |> Uid.Set.for_all (fun symbol ->
      match Uid.Map.find_opt symbol model_state with
      | None -> false
      | Some v -> not v)

let is_solvable_by (logics : 'k logic list) (f : (bool, 'k) Formula.t) : bool =
  let rec loop unsolved = function
    | [] -> IntSet.is_empty unsolved
    | (_solve, partition) :: rest ->
        let solvable, _unsolvable = partition f in
        let solvable = IntSet.of_list solvable in
        let unsolved = IntSet.diff unsolved solvable in
        if IntSet.is_empty unsolved then true
        else loop unsolved rest
  in
  loop (Formula.clause_indices_from f) logics

let check (logics : 'k logic list) (f : (bool, 'k) Formula.t)
    (keyset : Uid.Set.t) : 'k Solution.t =
  let clauses = Formula.clause_indices_from f in
  let solutions, solved_clauses =
    List.fold_left
      (fun (acc_sols, acc_solved) (solve, partition) ->
        let solvable, _unsolvable = partition f in
        let solvable_f = Formula.from_partition solvable f in
        ( solve solvable_f :: acc_sols,
          solvable |> IntSet.of_list |> IntSet.union acc_solved ))
      ([], IntSet.empty) logics
  in
  let clause_diff = IntSet.diff clauses solved_clauses in
  let were_all_clauses_solved = IntSet.is_empty clause_diff in
  if List.is_empty solutions || not were_all_clauses_solved then
    if List.is_empty solutions then Solution.Unsat else Solution.Unknown
  else
    let sat_models =
      solutions
      |> List.filter_map (function
        | Solution.Sat m -> Some m
        | Solution.Unknown -> None
        | Solution.Unsat -> None)
    in

    let domains =
      sat_models |> List.map (fun m -> m.Model.domain |> Uid.Set.of_list)
    in

    let rec is_pairwise_disjoint = function
      | [] -> true
      | d :: rest ->
          List.for_all (fun d' -> Uid.Set.is_empty (Uid.Set.inter d d')) rest
          && is_pairwise_disjoint rest
    in

    let covered = domains |> List.fold_left Uid.Set.union Uid.Set.empty in

    if is_pairwise_disjoint domains && Uid.Set.equal covered keyset then
      let merged_lookup uid =
        sat_models |> List.find_map (fun m -> m.Model.value (I uid))
      in
      let merged_model =
        Model.of_local (covered |> Uid.Set.to_list) ~lookup:merged_lookup
      in
      Solution.Sat merged_model
    else Solution.Unknown

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

let dpll ?(leftovers : Uid.t -> bool = fun _ -> Random.bool ())
    ?(to_symbol : int -> (bool, 'k) Symbol.t =
      fun i -> i |> Uid.of_int |> fun uid -> Symbol.B uid)
    ~(logics : 'k logic list) (solve_next : 'k solver)
    (f : (bool, 'k) Formula.t) : 'k Solution.t =
  if not (is_solvable_by logics f) then solve_next f
  else
    f |> Integer.to_propositional ~to_symbol |> fun (props, map) ->
    let keyset = Formula.symbols f in
    let decode = fun uid -> Uid.Map.find uid map in
    let clauses = Formula.clauses_from props in
    let rebuild_logical model =
      Formula.and_
        (model |> Uid.Map.to_list
        |> List.map (fun (uid, tv) ->
            let formula = decode uid in
            if tv then formula else Formula.not_ formula))
    in
    let rec dpll clauses model_state =
      let curr_keyset = clauses |> List.map Formula.symbols in
      if
        List.is_empty curr_keyset
        || List.exists (is_falsified_clause model_state) curr_keyset
      then
        if List.is_empty curr_keyset then
          (* 
           TODO: This means sat at the bool level, so try model_state solution...
        *)
          Solution.Unsat
        else Solution.Unsat
      else
        let is_trivial_true =
          match clauses with [ Const_bool true ] -> true | _ -> false
        in
        let is_sat =
          is_trivial_true
          || curr_keyset
             |> List.for_all (fun uids ->
                 uids
                 |> Uid.Set.exists (fun uid ->
                     match Uid.Map.find_opt uid model_state with
                     | None -> false
                     | Some v -> v))
        in
        if is_sat then
          let final_model =
            Uid.Map.add_seq
              (model_state |> Uid.Map.domain |> Uid.Set.to_seq
              |> Seq.map (fun key -> (key, leftovers key)))
              model_state
          in
          check logics (rebuild_logical final_model) keyset
        else
          let propped, model =
            clauses |> unit_propagate |> fun (e, partial) ->
            ( e,
              model_state |> Uid.Map.union (fun _ _ new_v -> Some new_v) partial
            )
          in
          match propped with
          | [] -> check logics (rebuild_logical model) keyset
          | ls when contains_const_false ls -> Solution.Unsat
          | propped ->
              let next_f = Formula.and_ propped in
              let branch_key = choose_literal propped in
              let uid = Symbol.to_uid branch_key in
              let true_model = Uid.Map.add uid true model in
              let true_clauses = Formula.clauses_from (
                Formula.subst true branch_key next_f
              ) in
              match true_clauses with
              | [ Const_bool true ] ->
                  check logics (rebuild_logical true_model) keyset
              | true_clauses -> (
                  match dpll true_clauses true_model with
                  | Solution.Unsat ->
                      let false_model = Uid.Map.add uid false model in
                      let false_clauses = Formula.clauses_from (
                        Formula.subst false branch_key next_f
                      ) in
                      dpll false_clauses false_model
                  | s -> s)
    in
    dpll clauses Uid.Map.empty |> function
    | Solution.Unknown -> solve_next f
    | s -> s

[@@@ocaml.warning "-48"]

let dpll_simplify : 'k simplifier =
  dpll
    ~to_symbol:(fun off ->
      off + Char.code 'p' |> Utils.Uid.of_int |> fun uid -> Symbol.B uid)
    ~logics:[ (Integer.solve_int_diff, Integer.partition_idl) ]

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  let pipeline = 
    propagate_constants 
    @> (fun next expr -> next (Integer.rewrite_bounds expr))
    @> dpll_simplify 
  in
  pipeline (direct_solve (module Oracle))
