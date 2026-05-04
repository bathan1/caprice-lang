open Utils

module IntSet = Iterables.IntSet

(** [int_symbol uid] is an int symbol with UID wrapped over a [Formula.Key] *)
let int_symbol (uid : Uid.t) = Formula.symbol (I uid)

(** [linearize formula] performs a few int-based heuristics to reduce FORMULA to an equisatisfiable formula. *)
let linearize (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t =
  match formula with
  | Formula.Binop
    ( ((Less_than_eq | Less_than) as binop),
    Binop (Plus, Key (I x), Key (I y)),
    Key (I z) ) when x = z ->
    Formula.binop binop (int_symbol y) (Formula.const_int 0)
  | Binop
    ( ((Less_than_eq | Less_than) as binop),
    Binop (Plus, Key (I x), Key (I y)),
    Key (I z) ) when y = z -> 
    Formula.binop binop (int_symbol x) (Formula.const_int 0)
  | Binop
    ( ((Less_than_eq | Less_than) as binop),
      (Binop (Plus, Key (I x), Const_int a) | Binop (Plus, Const_int a, Key (I x))),
      Const_int b ) ->
    Formula.binop binop (int_symbol x) (Formula.const_int (b - a))
  (* expr <= c  OR expr < c OR expr = c *)
  | Binop
    ( ((Less_than_eq | Less_than | Equal) as binop),
    Binop (((Plus | Minus) as op), Key (I a), Key (I b)),
    Const_int c ) -> (
      match op with
      | Plus ->
        (* a + b <= c  ==>  a <= c - b *)
        Formula.binop binop
          (int_symbol a)
          (Formula.binop Minus (Formula.const_int c) (int_symbol b))
      | Minus ->
        (* a - b <= c  ==>  a <= c + b *)
        Formula.binop binop
          (int_symbol a)
          (Formula.binop Plus (Formula.const_int c) (int_symbol b))
      | _ -> failwith "unreachable")
  (* c <= expr OR c < expr OR c = expr *)
  | Binop
    ( ((Less_than_eq | Less_than | Equal) as binop),
    Const_int c,
    Binop (((Plus | Minus) as op), Key (I a), Key (I b)) ) -> (
      match op with
      | Plus ->
        (* c <= a + b  ==>  c - b <= a *)
        Formula.binop binop
          (Formula.binop Minus (Formula.const_int c) (int_symbol b))
          (int_symbol a)
      | Minus ->
        (* c <= a - b  ==>  c + b <= a *)
        Formula.binop binop
          (Formula.binop Plus (Formula.const_int c) (int_symbol b))
          (int_symbol a)
      | _ -> failwith "unreachable")
  | f -> f

(** [to_propositional to_symbol formula] returns the boolean propositional formula form of FORMULA
    in the first element and the [Uid.t] to corresponding [Formula.t] atom map. *)
let to_propositional
    ?(to_symbol : int -> (bool, 'k) Symbol.t =
    fun uid -> uid |> Uid.of_int |> fun uid -> Symbol.B uid)
  (formula : (bool, 'k) Formula.t) =
  let counter = ref 0 in
  let hash = Hashtbl.create 32 in
  let get_next_symbol atomic = 
    let count = !counter in
    let prop_sym = to_symbol count in
    let resolved_uid = Symbol.to_uid prop_sym in
    counter := count + 1;
    Hashtbl.add hash resolved_uid atomic;
    Formula.symbol prop_sym
  in
  let rec to_bool_formula : type a. (a, 'k) Formula.t -> (bool, 'k) Formula.t =
    fun f ->
    match f with
    | Formula.Key (B bool_uid) ->
      get_next_symbol (Formula.symbol (B bool_uid))
    | Not (Binop (Equal, left, right)) ->
        Formula.not_ (get_next_symbol (Formula.binop Binop.Equal left right))
    | Binop (Less_than_eq, left, right) ->
        get_next_symbol (Formula.binop Less_than_eq left right)
    | Binop (Less_than, left, right) ->
        get_next_symbol (Formula.binop Less_than left right)
    | And ls -> Formula.and_ (List.map to_bool_formula ls)
    | expr ->
      failwith (
        Printf.sprintf "Can't map that to %s" (Formula.to_string ~uid:Symbol.AsciiSymbol.to_string expr)
      )
  in
  let bool_f = to_bool_formula formula in
  (bool_f, Hashtbl.to_seq hash |> Uid.Map.of_seq)

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
      |> List.filter (fun v -> lower < v && v < upper)
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

(** [prune clauses] drops redundant inequalities and neqs from CLAUSES

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
let prune : type k. (bool, k) Formula.t list -> (bool, k) Formula.t list =
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
  fun clauses ->
    let bounds_map, other_clauses = (
      List.fold_left collect_bounds (Uid.Map.empty, []) clauses
    ) in
    bounds_map 
    |> Uid.Map.to_list
    |> List.concat_map bound_to_formula_clauses
    |> fun rewritten -> rewritten @ other_clauses

(** [drop_redundant_ineqs formula] is FORMULA with redundant inequalities / disequalties dropped. *)
let drop_redundant_ineqs (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t =
  formula 
  |> Formula.clauses_from
  |> prune
  |> Formula.and_
