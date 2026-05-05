type 'k solver = (bool, 'k) Formula.t -> 'k Solution.t

type 'k simplifier = 'k solver -> 'k solver

type metadata =
  { was_backend_used : bool }

type 'k solver_with_metadata =
  (bool, 'k) Formula.t -> 'k Solution.t * metadata

type 'k simplifier_with_metadata =
  'k solver_with_metadata -> 'k solver_with_metadata

module type SOLVABLE = sig
  include Formula.S

  val solve : (bool, 'k) t -> 'k Solution.t
end

let direct_solve (module X : SOLVABLE) : 'k solver = fun e ->
  X.solve (Formula.transform (module X) e)

let _cdcl_T ~(t : 'k Theory.t_solver) (formula : (bool, 'k) Formula.t) : 'k Solution.t =
  let conn = Connector.make () in
  let smt_clauses = Theory.from_smt_formula (Formula.clauses_from formula) in
  let propositional = Connector.abstract conn smt_clauses in
  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | None -> Solution.Unsat
    | Some model ->
        let smt_lits = Connector.literals_from_model conn model in
        match t smt_lits with
        | Theory_sat model -> Solution.Sat model
        | Theory_unsat core ->
            let learned = Connector.theory_learn conn core in
            loop conn (Sat.Formula.conjoin1 sat_formula learned)

  in
  loop conn propositional

let cdcl_T
  ~(ts : (module Theory.THEORY) list)
  (formula : (bool, 'k) Formula.t)
  : 'k Solution.t =
  let accepts =
    List.map (fun (module T : Theory.THEORY) -> T.accepts) ts
  in

  let conn = Connector.make () in

  let smt_clauses =
    Theory.from_smt_formula (Formula.clauses_from formula)
  in

  let propositional =
    Connector.abstract conn smt_clauses
  in

  let interface_eqs =
    Theory.interface
      ~accepts
      smt_clauses
  in

  let interface_tautologies =
    interface_eqs
    |> List.map (fun lit ->
      let sat_lit =
        Connector.abstract_literal conn lit
      in
      [ sat_lit; Sat.Formula.negate sat_lit ])
  in

  let propositional =
    List.fold_left
      Sat.Formula.conjoin1
      propositional
      interface_tautologies
  in

  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | None ->
      Solution.Unsat

    | Some model ->
      let smt_lits =
        Connector.literals_from_model conn model
      in
      let t_solutions =
        List.mapi
          (fun _i (module T : Theory.THEORY) ->
            let accepted =
              List.filter T.accepts smt_lits
            in
            T.solve accepted)
          ts
      in

      let cores =
        Theory.find_unsat_cores t_solutions
      in

      begin match cores with
        | [] ->
          let arrangement =
            smt_lits
            |> List.filter Theory.is_positive_interface_equality
          in
          let models =
            t_solutions
            |> List.filter_map (function
              | Theory.Theory_sat model -> Some model
              | _ -> None)
          in
          let merged =
            Euf.merge_models ~arrangement ~models
            |> Euf.to_model
          in
          Solution.Sat merged
        | cores ->
          let sat_formula' =
            List.fold_left
              (fun acc core ->
                let learned =
                  Connector.theory_learn conn core
                in
                Sat.Formula.conjoin1 acc learned)
              sat_formula
              cores
          in
          loop conn sat_formula'
        end
  in

  loop conn propositional

let rec collect_concrete
    (acc : Model.ValueMap.t)
    (f : (bool, 'k) Formula.t)
  : Model.ValueMap.t option =
  match f with
  | Binop (Equal, Key (I k), Const_int i)
  | Binop (Equal, Const_int i, Key (I k)) ->
      Model.ValueMap.add_int_checked k i acc
  | Binop (Equal, Key (B k), Const_bool b)
  | Binop (Equal, Const_bool b, Key (B k)) ->
      Model.ValueMap.add_bool_checked k b acc
  | Key (B k) ->
      Model.ValueMap.add_bool_checked k true acc
  | Not (Key (B k)) ->
      Model.ValueMap.add_bool_checked k false acc
  | And ls ->
      List.fold_left
        (fun acc_opt f ->
          match acc_opt with
          | None -> None
          | Some acc -> collect_concrete acc f)
        (Some acc)
        ls
  | _ -> Some acc

(** [implied_concretization next expr] first attempts to solve EXPR with a 
    few heuristics, and then calls the solver NEXT.

    This simply special-cases on some common formulas. It also extracts out
    constant assignments (variable = constant).

    As more simplifiers are added, we could instead name this after implied
    concretization. *)
let implied_concretization : 'k simplifier = fun next expr ->
  let open Utils in
  let module ValueMap = Model.ValueMap in
  match collect_concrete Uid.Map.empty expr with
  | None -> Solution.Unsat (* because a variable can't be equal to more than 2 *)
  | Some value_map ->
    let rec sub_concrete_key : type a. (a, 'k) Formula.t  -> (a, 'k) Formula.t =
      fun f ->
      match f with
      | Key (I key) ->
        begin match ValueMap.find_int_opt key value_map with
        | Some iv -> Formula.const_int iv
        | None -> Formula.symbol (I key)
        end
      | Key (B key) -> 
        begin
        match ValueMap.find_bool_opt key value_map with
        | Some iv -> Formula.const_bool iv
        | None -> Formula.symbol (B key)
        end
      | Binop (Less_than, left, right) ->
        Formula.binop Binop.Less_than
          (sub_concrete_key left)
          (sub_concrete_key right)
      | Binop (Less_than_eq, left, right) ->
          Formula.binop Binop.Less_than_eq
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Plus, left, right) ->
          Formula.binop Binop.Plus
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Minus, left, right) ->
          Formula.binop Binop.Minus
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Times, left, right) ->
          Formula.binop Binop.Times
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Divide, left, right) ->
          Formula.binop Binop.Divide
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Modulus, left, right) ->
          Formula.binop Binop.Modulus
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Binop (Equal, left, right) ->
          Formula.binop Binop.Equal
            (sub_concrete_key left)
            (sub_concrete_key right)
      | Not f -> Formula.not_ (sub_concrete_key f)
      | And ls -> Formula.and_ @@ List.map sub_concrete_key ls
      | f -> f
    in
    let simplified = sub_concrete_key expr in
    match simplified with
    | Const_bool true -> Solution.Sat (Model.from_value_map value_map)
    | Const_bool false -> Solution.Unsat
    | _ ->
    next simplified

let linearize next expr = next (Integer.linearize expr)
let drop_redundant_ineqs next expr = next (Integer.drop_redundant_ineqs expr)
let contains_unsolvable_binop formula =
  Formula.contains_binop Times formula
  || Formula.contains_binop Divide formula
  || Formula.contains_binop Modulus formula
  || Formula.contains_binop Plus formula

let blue3_solve formula =
  cdcl_T
    ~ts:[
      (module Euf : Theory.THEORY);
      (module Idl : Theory.THEORY);
    ]
    formula

let blue3 ~(threshold : int) (next : 'k solver) (formula : (bool, 'k) Formula.t) =
  if contains_unsolvable_binop formula then next formula
  else
    match formula with
    | Const_bool true -> Solution.Sat Model.empty
    | Const_bool false -> Solution.Unsat
    | _ ->
      let formula', num_cases = Idl.split_cases formula in
      if num_cases > threshold then next formula
      else
        match blue3_solve formula' with
        | Solution.Unknown -> next formula
        | solution -> solution

let blue3_with_metadata
  ~(threshold : int)
  (next : 'k solver_with_metadata)
  (formula : (bool, 'k) Formula.t)
  : 'k Solution.t * metadata =
  if contains_unsolvable_binop formula then
    next formula
  else
    match formula with
    | Const_bool true ->
        Solution.Sat Model.empty, { was_backend_used = false }

    | Const_bool false ->
        Solution.Unsat, { was_backend_used = false }

    | _ ->
        let formula', num_cases = Idl.split_cases formula in
        if num_cases > threshold then
          next formula
        else
          match blue3_solve formula' with
          | Solution.Unknown ->
              next formula

          | solution ->
              solution, { was_backend_used = false }

let with_metadata (simplifier : 'k simplifier)
  : 'k simplifier_with_metadata =
  fun next formula ->
    let metadata = ref { was_backend_used = false } in

    let next_plain formula =
      let solution, metadata' = next formula in
      metadata := metadata';
      solution
    in

    let solution =
      simplifier next_plain formula
    in

    solution, !metadata

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

let ( @@>> )
  : 'k simplifier_with_metadata ->
    'k simplifier_with_metadata ->
    'k simplifier_with_metadata =
  fun f g -> fun solve -> f (g solve)

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  (* let ascii_key k = Symbol.AsciiSymbol.to_string @@ Model.uid_from_key k in *)
  let pipeline =
    linearize
    @@> implied_concretization
    @@> drop_redundant_ineqs
    @@> blue3 ~threshold:6
  in
  pipeline (direct_solve (module Oracle))

let main_solve_with_metadata (module Oracle : SOLVABLE)
  : 'k solver_with_metadata =
  let pipeline =
    with_metadata linearize
    @@>> with_metadata implied_concretization
    @@>> with_metadata drop_redundant_ineqs
    @@>> blue3_with_metadata ~threshold:6
  in

  pipeline
    (fun formula ->
       direct_solve (module Oracle) formula,
       { was_backend_used = true })
