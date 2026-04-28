open Utils

module IntSet = Iterables.IntSet

(** [int_symbol uid] is an int symbol with UID wrapped over a [Formula.Key]
*)
let int_symbol (uid : Uid.t) = Formula.symbol (I uid)

(** [linearize formula] performs a few int-based heuristics to reduce FORMULA to an equisatisfiable formula.
*)
let linearize formula =
  match formula with
  | Formula.Binop
    ( ((Less_than_eq | Less_than) as binop),
    Binop (Plus, Key (I x), Key (I y)),
    Key (I z) )
    when x = z ->
    Formula.binop binop (int_symbol y) (Formula.const_int 0)
  | Binop
    ( ((Less_than_eq | Less_than) as binop),
    Binop (Plus, Key (I x), Key (I y)),
    Key (I z) )
    when y = z -> Formula.binop binop (int_symbol x) (Formula.const_int 0)
  | Binop
    (
      ((Less_than_eq | Less_than) as binop),
      (
        Binop (Plus, Key (I x), Const_int a)
        | Binop (Plus, Const_int a, Key (I x))
      ),
      Const_int b
    ) ->
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
    in the first element and the [Uid.t] to corresponding [Formula.t] atom map.
*)
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
    | Formula.Not (Binop (Equal, left, right)) ->
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

type int_constraint = {
  lower : int;
  upper : int;
  neq : int list;
}

let bound_to_formula_clauses (uid, { lower; upper; neq; } : Uid.t * int_constraint) =
  let is_impossible_bound = lower > upper in
  if is_impossible_bound then
    [ Formula.const_bool false ]
  else
    let variable = Formula.symbol (I uid) in
    let neq_formulas =
      neq 
      |> List.filter (fun v -> lower < v && v < upper)
      |> List.map (fun v ->
        Formula.binop Not_equal variable (Formula.const_int v)
      )
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
    ]}
*)
let prune : type k. (bool, k) Formula.t list -> (bool, k) Formula.t list =
  let find_or_default key map =
    match Uid.Map.find_opt key map with
    | Some v -> v
    | None ->
      {
        lower = Int.min_int;
        (* greatest lower bound *)
        upper = Int.max_int;
        (* lowest upper bound *)
        neq = [];
        (* not equal list *)
      }
  in
  let collect_bounds = 
    fun (acc, other) clause ->
      match clause with
      | Formula.Not (Binop (Equal, Key (I key), Const_int c)) ->
        let { lower; upper; neq; } = find_or_default key acc in
        let next_neq_set = c :: neq in
        let next =
          Uid.Map.add key { lower; upper; neq = next_neq_set; } acc
        in
        (next, other)
      (* eq case *)
      | Formula.Binop (Equal, Const_int c, Key (I key))
      | Formula.Binop (Equal, Key (I key), Const_int c) ->
        let { neq; _ } = find_or_default key acc in
        let next =
          Uid.Map.add key { lower = c; upper = c; neq; } acc
        in
        (next, other)
      (* lower bounds *)
      | Binop (Less_than_eq, Const_int c, Key (I key)) ->
        let { lower; upper; neq; } = find_or_default key acc in
        let next =
          Uid.Map.add key { lower = max lower c; upper; neq; } acc
        in
        (next, other)
      | Binop (Less_than, Const_int c, Key (I key)) ->
        let { lower; upper; neq; } = find_or_default key acc in
        let next =
          Uid.Map.add key
            { lower = max lower (c + 1); upper; neq; }
            acc
        in
        (next, other)
      (* upper bounds *)
      | Binop (Less_than_eq, Key (I key), Const_int c) ->
        let { lower; upper; neq; } = find_or_default key acc in
        let next =
          Uid.Map.add key { lower; upper = min upper c; neq; } acc
        in
        (next, other)
      | Binop (Less_than, Key (I key), Const_int c) ->
        let { lower; upper; neq; } = find_or_default key acc in
        let next =
          Uid.Map.add key
            { lower; upper = min upper (c - 1); neq; }
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

(** [rewrite_bounds f] is F with redundant inequalities / disequalties dropped.
*)
let rewrite_bounds : type k. (bool, k) Formula.t -> (bool, k) Formula.t =
  fun f ->
  let open Formula in
  let int_symbol key = symbol (I key) in
  let handle_neq left right =
    let right_minus_one = binop Minus right (const_int 1) in
    let right_plus_one = binop Plus right (const_int 1) in
    let left_ineq = binop Less_than_eq left right_minus_one in
    let right_ineq = binop Less_than_eq right_plus_one left in
    binop Or left_ineq right_ineq
  in
  let rec normalize_unit : type a. (a, k) t -> (a, k) t = function
    | And ls -> and_ (List.map normalize_unit ls)
    (* neqs into disjunctions that bellman ford can solve *)
    | Not (Binop (Equal, Key (I left), Key (I right))) ->
      handle_neq (int_symbol left) (int_symbol right)
    (* x != C *)
    | Not (Binop (Equal, Key (I key), Const_int c)) ->
      handle_neq (int_symbol key) (const_int c)
    | f -> f
  in
  f 
  |> Formula.clauses_from
  |> List.map linearize
  |> prune
  |> List.map normalize_unit
  |> Formula.and_

type var = Symbol_key of Uid.t | Z0

type diff_constraint = {
  x : var;  (** Variable id to subtract. *)
  y : var;  (** Variable id that subtracts [x]. *)
  c : int;  (** Intepreted as an int {i literal} *)
}

(** [to_diff_constraints formula] returns the list of integer difference 
    constraints in FORMULA.
*)
let rec to_diff_constraints (formula : (bool, 'k) Formula.t)
  : diff_constraint list =
  match formula with
  (* x = c -> (x - 0 <= c) and (0 - y) <= -c *)
  | Binop (Equal, Key (I x), Const_int c)
    ->
    [ { x = Symbol_key x; y = Z0; c }; { x = Z0; y = Symbol_key x; c = -c } ]
  (* x = y -> (x - y) <= 0 and (y - x) <= 0 *)
  | Binop (Equal, Key (I x), Key (I y)) ->
    [
      { x = Symbol_key x; y = Symbol_key y; c = 0 };
      { x = Symbol_key y; y = Symbol_key x; c = 0 };
    ]
  (* x <= y -> (x - y <= 0)
        y >= x -> (x - y <= 0)
        not (x > y) -> x <= y -> (x - y) <= 0 *)
  | Binop (Less_than_eq, Key (I x), Key (I y)) ->
    [ { x = Symbol_key x; y = Symbol_key y; c = 0 } ]
  (* x <= c -> (x - 0) <= c
        c >= x -> (x - 0) <= c
        not (x > c) -> x <= c -> (x - 0) <= c *)
  | Binop (Less_than_eq, Key (I x), Const_int c) ->
    [ { x = Symbol_key x; y = Z0; c } ]
  (* x < c -> x - 0 <= c - 1 *)
  | Binop (Less_than, Key (I x), Const_int c) ->
    [ { x = Symbol_key x; y = Z0; c = c - 1 } ]
  (* x >= c -> 0 - x <= -c
       not (x < c) -> x >= c -> (0 - x) <= -c *)
  | Binop (Less_than_eq, Const_int c, Key (I x)) ->
    [ { x = Z0; y = Symbol_key x; c = -c } ]
  (* x > c -> (0 - x) <= -(c + 1) *)
  | Binop (Less_than, Const_int c, Key (I x)) ->
    [ { x = Z0; y = Symbol_key x; c = -(c + 1) } ]
  (* x > y -> (y - x) <= -1 (difference is at least 1) *)
  | Binop (Less_than, Key (I y), Key (I x)) ->
    [ { x = Symbol_key y; y = Symbol_key x; c = -1 } ]
  (* x + c <= y  ->  x - y <= -c *)
  | Binop (Less_than_eq, Binop (Plus, Key (I x), Const_int c), Key (I y))
    | Binop (Less_than_eq, Binop (Plus, Const_int c, Key (I x)), Key (I y)) ->
    [ { x = Symbol_key x; y = Symbol_key y; c = -c } ]
  (* y <= x + c  ->  y - x <= c *)
  | Binop (Less_than_eq, Key (I y), Binop (Plus, Key (I x), Const_int c))
    | Binop (Less_than_eq, Key (I y), Binop (Plus, Const_int c, Key (I x))) ->
    [ { x = Symbol_key y; y = Symbol_key x; c } ]
  (* x - c <= y  ->  x - y <= c *)
  | Binop (Less_than_eq, Binop (Minus, Key (I x), Const_int c), Key (I y)) ->
    [ { x = Symbol_key x; y = Symbol_key y; c } ]
  (* y <= x - c  ->  y - x <= -c *)
  | Binop (Less_than_eq, Key (I y), Binop (Minus, Key (I x), Const_int c)) ->
    [ { x = Symbol_key y; y = Symbol_key x; c = -c } ]
  | And exprs -> List.concat_map to_diff_constraints exprs
  | _ -> []

(** [to_constraint_graph formula] returns the 3-tuple graph representation
    (NODES, EDGES, UID_TO_INDEX) of FORMULA, where:
    - NODES is number of unique variables in FORMULA + 2
    - EDGES is a 3-tuple (SRC, DST, WEIGHT)
    - UID_TO_INDEX maps UIDs from FORMULA to their node id (index)

    Index [0] is reserved for a dummy root node and index [NODES - 1]
    is reserved for the special "zero constant" node.
*)
let to_constraint_graph (formula : (bool, 'k) Formula.t)
  : nodes:int * edges:(int * int * int) array * int Uid.Map.t =
  let constraints = to_diff_constraints formula in
  List.concat_map (fun {x; y; _} ->
    match (x, y) with
    | Symbol_key x, Symbol_key y -> [ x; y ]
    | Symbol_key key, Z0 | Z0, Symbol_key key -> [ key ]
    | _ -> []
  ) constraints
  |> List.sort_uniq Uid.compare
  |> List.mapi (fun i uid -> (uid, i + 1)) (* Reserve index 0 for super-root node *)
  |> Uid.Map.of_list
  |> fun key_to_index -> (
    let nodes =
      1 + Uid.Map.cardinal key_to_index + 1
    (* [0; x; y; z0] *)
    in
    let get_index x = Uid.Map.find x key_to_index in
    let edges_constraints =
      constraints
      |> List.filter_map (fun { x; y; c } ->
        match (x, y) with
        | Symbol_key x, Symbol_key y -> Some (get_index x, get_index y, c)
        | Symbol_key x, Z0 -> Some (get_index x, nodes - 1, c)
        | Z0, Symbol_key y -> Some (nodes - 1, get_index y, c)
        | _ -> None)
    in
    let dummy_root_edges = List.init nodes (fun i -> (0, i, 0)) in
    let edges = Array.of_list (edges_constraints @ dummy_root_edges) in
    (~nodes, ~edges, key_to_index)
  )

(** [is_idl_clause formula] returns true if FORMULA 
    can be meaningfully decoded by the formula to bellman-ford graph
    decoder [graph_constraints].
*)
let is_idl_clause : type a k. (a, k) Formula.t -> bool =
  fun formula ->
  match formula with
  | Binop (Less_than, Key (I _), Key (I _))
  | Binop (Less_than_eq, Key (I _), Key (I _))
  | Binop (Less_than, Const_int _, Key (I _))
  | Binop (Less_than_eq, Const_int _, Key (I _))
  | Binop (Less_than, Key (I _), Const_int _)
  | Binop (Less_than_eq, Key (I _), Const_int _) -> true
  | _ -> false

(** [is_idl_solvable formula] returns if all clauses in FORMULA can be solved 
    with bellman ford for difference logic
*)
let is_idl_solvable (formula : (bool, 'k) Formula.t) : bool =
  let rec contains_idl_clause : type a k. (a, k) Formula.t -> bool =
    fun formula ->
    match formula with
    | Formula.And clauses ->
        List.for_all contains_idl_clause clauses
    | Binop (Or, left, right) -> 
      contains_idl_clause left && contains_idl_clause right
    | clause ->
        is_idl_clause clause
  in
  contains_idl_clause formula

exception Graph_disconnected of int

(** [bellman_ford src nodes edges] returns the shortest paths to each node from SRC    if there is no negative cycle. Otherwise, it catches that and returns the 
    cycle as a list.
*)
let bellman_ford ~(src : int) (nodes : int) (edges : (int * int * int) array) =
  let init =
    ( Array.init nodes (fun i -> if i = src then Some 0 else None),
      Array.init nodes (fun _ : int option -> None) )
  in
  let vertices = Array.init nodes (fun i -> i) in
  let relax_distances =
    fun (distance, predecessor) (u, v, w) ->
    match (distance.(u), distance.(v)) with
    | None , _ -> (distance, predecessor)
    | Some du, None ->
      let () =
        distance.(v) <- Some (du + w);
        predecessor.(v) <- Some u
      in
      (distance, predecessor)
    | Some du, Some dv ->
      let () =
        if du + w < dv then distance.(v) <- Some (du + w);
        predecessor.(v) <- Some u
      in
      (distance, predecessor)
  in
  let distance, predecessor =
    Array.fold_left
      (fun (distance, predecessor) i ->
        if i = nodes - 1 then (distance, predecessor)
        else Array.fold_left relax_distances (distance, predecessor) edges)
      init vertices
  in
  let rec find_cycle_start i =
    if i >= Array.length edges then None
    else
      let u, v, w = edges.(i) in
      match (distance.(u), distance.(v)) with
      | None, _ -> raise (Graph_disconnected u)
      | _, None -> raise (Graph_disconnected v)
      | Some du, Some dv when du + w < dv -> Some v
      | _ -> find_cycle_start (i + 1)
  in
  match find_cycle_start 0 with
  | None -> `No_negative_cycle (Array.map (Option.value ~default:Int.max_int) distance, predecessor)
  | Some vertex ->
    let rec move_back x i =
      if i = 0 then x
      else
        match predecessor.(x) with
        | None -> x
        | Some parent -> move_back parent (i - 1)
    in
    let cycle_vertex = move_back vertex nodes in
    let rec collect_cycle curr acc =
      if List.mem curr acc then curr :: acc
      else
        match predecessor.(curr) with
        | None -> curr :: acc
        | Some parent -> collect_cycle parent (curr :: acc)
    in
    `Negative_cycle (collect_cycle cycle_vertex [])

(** [solve_diff formula] finds the tightest upper bounds of each integer variable in FORMULA

    {[
    open Smt

    module AsciiSymbol = Symbol.AsciiSymbol

    let () =
      let key c = Formula.symbol (AsciiSymbol.make_int c) in
      in
      let formula = Formula.and_ [
        Formula.binop Less_than_eq (key 'a') (Formula.const_int 2);
        Formula.binop Greater_than (key 'b') (key 'a');
      ] 
      in
      match Integer.solve_diff formula with
      | Solution.Sat model ->
          (* Access a (tight) upper bound: model.value (I 0) -> int option *)
          printf "SAT: upper bound on x = %d\n"
            (Option.value_exn (model.value (I 0)))
      | Unsat ->
          printf "UNSAT\n"
    ]}
*)
let solve_idl (formula : (bool, 'k) Formula.t) : 'k Solution.t =
  let (~nodes, ~edges, key_to_index) = to_constraint_graph formula in
  match bellman_ford nodes edges ~src:0 with
  | `Negative_cycle _ -> Solution.Unsat
  | `No_negative_cycle (distances, _) ->
    let offset = distances.(nodes - 1) in
    let local_model = Uid.Map.map (fun index ->
        Model.Int (offset - distances.(index))
      ) key_to_index
    in
    let model = Model.from_value_map local_model in
    Solution.Sat model
