open Utils

type affine =
  | Const of int
  | Var_plus_const of Uid.t * int

let add_affine a b =
  match a, b with
  | Const x, Const y -> Some (Const (x + y))
  | Var_plus_const (x, c), Const k
  | Const k, Var_plus_const (x, c) -> Some (Var_plus_const (x, c + k))
  | Var_plus_const _, Var_plus_const _ -> None

let sub_affine a b =
  match a, b with
  | Const x, Const y -> Some (Const (x - y))
  | Var_plus_const (x, c), Const k -> Some (Var_plus_const (x, c - k))
  | Const _, Var_plus_const (_, _) -> None
  | Var_plus_const _, Var_plus_const _ -> None

let rec affine_from_formula_opt
  : type a k. (a, k) Formula.t -> affine option =
  function
  | Const_int c -> Some (Const c)
  | Key (I x) -> Some (Var_plus_const (x, 0))
  | Binop (Plus, left, right) ->
    begin match affine_from_formula_opt left, affine_from_formula_opt right with
    | Some l, Some r -> add_affine l r
    | _ -> None
    end
  | Binop (Minus, left, right) ->
    begin match affine_from_formula_opt left, affine_from_formula_opt right with
    | Some l, Some r -> sub_affine l r
    | _ -> None
    end
  | _ -> None

let formula_from_affine : type k. affine -> (int, k) Formula.t =
  function
  | Const c -> Formula.const_int c
  | Var_plus_const (x, c) when c > 0 -> Formula.plus (Formula.symbol (Symbol.I x)) (Formula.const_int c)
  | Var_plus_const (x, c) -> Formula.minus (Formula.symbol (Symbol.I x)) (Formula.const_int (-c))

let formula_from_affine_comparison
  : type k.
    (int * int * bool) Binop.t ->
    affine ->
    affine ->
    (bool, k) Formula.t option =
  fun binop left right ->
    match left, right with
    | Var_plus_const (x, cx), Const c ->
      (* x + cx op c  ==>  x op c - cx *)
      Some
        (Formula.binop
            binop
            (Formula.symbol (I x))
            (Formula.const_int (c - cx)))
    | Const c, Var_plus_const (x, cx) ->
      (* c op x + cx  ==>  c - cx op x *)
      Some
        (Formula.binop
            binop
            (Formula.const_int (c - cx))
            (Formula.symbol (I x)))
    | Const c1, Const c2 -> Some (Formula.binop binop (Formula.const_int c1) (Formula.const_int c2))
    | Var_plus_const (x, cx), Var_plus_const (y, cy) when Uid.equal x y ->
      (* x + cx op x + cy  ==>  cx op cy *)
      Some
        (Formula.binop
          binop
          (Formula.const_int cx)
          (Formula.const_int cy))
    | Var_plus_const _, Var_plus_const _ -> None

type int_constraint =
  { lower : int
  ; upper : int
  ; neq : int list
  ; eq : int list
  }

let bound_to_formula_clauses (uid, { lower ; upper ; neq ; eq } : Uid.t * int_constraint) =
  let over_one_eq eq =
    eq
    |> List.sort_uniq Int.compare
    |> function
      | [] -> false
      | _ :: [] -> false
      | _ -> true
  in
  let has_conflicting_eqs neq =
    List.exists (fun n -> List.mem n eq) neq
  in
  if lower > upper
    then [Formula.const_bool false]
  else if over_one_eq eq
    then [Formula.const_bool false]
  else if has_conflicting_eqs neq
    then [Formula.const_bool false]
  else
    let variable = Formula.symbol (I uid) in
    let neq_formulas =
      neq
      |> List.filter (fun v -> lower <= v && v <= upper)
      |> List.map (fun v ->
        Formula.binop Not_equal variable (Formula.const_int v))
    in
    if lower = upper then
      Formula.binop Equal variable (Formula.const_int lower)
      :: neq_formulas
    else
      let lower_neq = List.find_opt (fun v -> v = lower) neq in
      let upper_neq = List.find_opt (fun v -> v = upper) neq in
      let resolved_lower, resolved_upper =
        match (lower_neq, upper_neq) with
        | None, None -> (lower, upper)
        (* drop neq and increment lower bound *)
        | Some lower_bound_neq, None -> (lower_bound_neq + 1, upper)
        (* drop neq and decrement upper bound *)
        | None, Some upper_bound_neq -> (lower, upper_bound_neq - 1)
        | Some lower_bound_eq, Some upper_bound_eq ->
          (lower_bound_eq + 1, upper_bound_eq - 1)
      in
      let lower_bound =
        match resolved_lower with
        | lb when lb = Int.min_int -> None
        | lb -> Some (Formula.binop Less_than_eq (Formula.const_int lb) variable)
      in
      let upper_bound =
        match resolved_upper with
        | ub when ub = Int.max_int -> None
        | ub -> Some (Formula.binop Less_than_eq variable (Formula.const_int ub))
      in
      match lower_bound, upper_bound with
      | None, None -> neq_formulas
      | Some bound, None | None, Some bound -> bound :: neq_formulas
      | Some lb, Some ub -> lb :: ub :: neq_formulas

(** [prune_redundant clauses] drops redundant inequalities and neqs from CLAUSES

    For example, (a >= 2) ^ (a != 1) would turn into (a >= 2)
    because (a != 1) is implied by (a >= 2).
    {[
    open Smt

    module AsciiSymbol = Symbol.AsciiSymbol

    let () =
      let key c = Formula.symbol (AsciiSymbol.make_int c) in
      in
      let formula = Formula.and_ [
        Formula.binop Greater_than_eq (key 'a') (Formula.const_int 2);
        Formula.binop Not_equal (key 'a') (Formula.const_int 1);
      ]
      in
      let pruned_formula = Integer.prune formula in
      Printf.printf "%s\n" (Formula.to_string pruned_formula)
      (* "(a >= 2)" *)
    ]} *)
let prune_redundant (clauses : (bool, 'k) Formula.t list) : (bool, 'k) Formula.t list =
  let find_or_default key map =
    match Uid.Map.find_opt key map with
    | Some v -> v
    | None ->
      { lower = Int.min_int
      ; upper = Int.max_int
      ; neq = []
      ; eq = []
      }
  in
  let collect_bounds =
    fun (acc, other) clause ->
      match clause with
      | Formula.Not (Binop (Equal, Key (I key), Const_int c)) ->
        let { lower ; upper ; neq ; eq } = find_or_default key acc in
        let next_neq_set = c :: neq in
        let next =
          Uid.Map.add key { lower ; upper ; neq = next_neq_set ; eq } acc
        in
        (next, other)
      (* eq case *)
      | Formula.Binop (Equal, Const_int c, Key (I key))
      | Formula.Binop (Equal, Key (I key), Const_int c) ->
        let current = find_or_default key acc in
        let next =
            Uid.Map.add key { current with eq = c :: current.eq } acc
        in
        (next, other)
      (* lower bounds *)
      | Binop (Less_than_eq, Const_int c, Key (I key)) ->
        let { lower ; upper ; neq ; eq } = find_or_default key acc in
        let next =
          Uid.Map.add key { lower = max lower c ; upper ; neq ; eq } acc
        in
        (next, other)
      | Binop (Less_than, Const_int c, Key (I key)) ->
      let { lower ; upper ; neq ; eq } = find_or_default key acc in
        let next =
          Uid.Map.add key
            { lower = max lower (c + 1) ; upper ; neq ; eq }
            acc
        in
        (next, other)
      (* upper bounds *)
      | Binop (Less_than_eq, Key (I key), Const_int c) ->
        let { lower ; upper ; neq ; eq } = find_or_default key acc in
        let next =
          Uid.Map.add key { lower ; upper = min upper c ; neq ; eq } acc
        in
        (next, other)
      | Binop (Less_than, Key (I key), Const_int c) ->
        let { lower ; upper ; neq ; eq } = find_or_default key acc in
        let next =
          Uid.Map.add key
            { lower ; upper = min upper (c - 1) ; neq ; eq }
            acc
        in
        (next, other)
      | f -> (acc, f :: other)
  in
  let bounds_map, other_clauses =
    List.fold_left collect_bounds (Uid.Map.empty, []) clauses
  in
  bounds_map
  |> Uid.Map.to_list
  |> List.concat_map bound_to_formula_clauses
  |> fun rewritten -> rewritten @ other_clauses

let reflect_int_opt : type a k. (a, k) Formula.t -> (int, k) Formula.t option = fun term ->
  term
  |> affine_from_formula_opt
  |> Option.map formula_from_affine

let rec linearize (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t =
  match formula with
  | Formula.Binop
    (((Equal | Less_than | Less_than_eq) as binop),
      left,
      right) ->
    begin match affine_from_formula_opt left, affine_from_formula_opt right with
    | Some l, Some r ->
        begin match formula_from_affine_comparison binop l r with
        | Some formula' -> formula'
        | None -> formula
        end
    | _ -> formula
    end
  | Formula.And ls -> Formula.and_ (List.map linearize ls)
  | Formula.Not f -> Formula.not_ (linearize f)
  | f -> f

let drop_redundant_ineqs (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t =
  formula
  |> Formula.clauses_from
  |> prune_redundant
  |> Formula.and_
